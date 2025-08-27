# Gemini API 배치 모니터링 및 결과 처리 스크립트
# 목적: 배치 작업 상태 모니터링, 완료된 데이터 다운로드 및 파싱 전담
# 특징: 05 스크립트에서 요청한 배치 작업의 후속 처리 담당

# 설정 및 유틸리티 로드 (오류 처리 포함)
cat("📂 종속 파일 로드 중...\n")

tryCatch({
  source("libs/config.R")
  cat("✅ config.R 로드 완료\n")
}, error = function(e) {
  stop("❌ config.R 로드 실패: ", e$message)
})

tryCatch({
  source("libs/utils.R")
  cat("✅ utils.R 로드 완료\n")
}, error = function(e) {
  stop("❌ utils.R 로드 실패: ", e$message)
})

tryCatch({
  source("modules/analysis_tracker.R")
  cat("✅ analysis_tracker.R 로드 완료\n")
}, error = function(e) {
  stop("❌ analysis_tracker.R 로드 실패: ", e$message)
})

tryCatch({
  source("modules/adaptive_sampling.R")
  cat("✅ adaptive_sampling.R 로드 완료\n")
}, error = function(e) {
  stop("❌ adaptive_sampling.R 로드 실패: ", e$message)
})

# 필요한 패키지 로드
cat("📦 필요한 패키지 확인 중...\n")
required_packages <- c("dplyr", "stringr", "jsonlite", "httr2", "readr", "R6")

# 설치되지 않은 패키지 확인
tryCatch({
  new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
  if(length(new_packages) > 0) {
    cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
    install.packages(new_packages, dependencies = TRUE, quiet = TRUE)
  }
}, error = function(e) {
  cat("⚠️ 패키지 설치 중 오류:", e$message, "\n")
})

# 패키지 로드
cat("📚 패키지 로드 중...\n")
for(pkg in required_packages) {
  tryCatch({
    library(pkg, character.only = TRUE, quietly = TRUE)
    cat(sprintf("✅ %s 로드 완료\n", pkg))
  }, error = function(e) {
    cat(sprintf("❌ %s 로드 실패: %s\n", pkg, e$message))
    stop("필수 패키지 로드 실패")
  })
}

# 배치 처리 설정은 config.R에서 로드됨
cat("⚙️ 배치 설정 확인 중...\n")
if (!exists("BATCH_CONFIG")) {
  stop("❌ BATCH_CONFIG가 로드되지 않았습니다. config.R를 확인해주세요.")
}
cat("✅ 배치 설정 로드 완료\n")

# API 키 확인
cat("🔑 API 키 확인 중...\n")
api_key <- Sys.getenv("GEMINI_API_KEY")
if (api_key == "") {
  cat("⚠️ GEMINI_API_KEY 환경 변수가 설정되지 않았습니다.\n")
} else {
  cat(sprintf("✅ API 키 확인 완료 (길이: %d문자)\n", nchar(api_key)))
}

# 분석 이력 추적기 초기화
cat("📋 분석 이력 추적기 초기화 중...\n")
tryCatch({
  tracker <- AnalysisTracker$new()
  cat("✅ 분석 이력 추적기 초기화 완료\n")
}, error = function(e) {
  stop("❌ 분석 이력 추적기 초기화 실패: ", e$message)
})

# 배치 모니터링 및 결과 처리 전담 클래스
BatchMonitor <- R6Class("BatchMonitor",
  public = list(
    api_key = NULL,
    base_url = "https://generativelanguage.googleapis.com/v1beta",
    
    initialize = function() {
      self$api_key <- Sys.getenv("GEMINI_API_KEY")
      if (self$api_key == "") {
        stop("⚠️ Gemini API 키가 설정되지 않았습니다.")
      }
      log_message("INFO", "배치 모니터 초기화 완료")
    },
    
    # 1. 단일 배치 작업 상태 확인
    check_batch_status = function(batch_name) {
      tryCatch({
        response <- httr2::request(sprintf("%s/%s", self$base_url, batch_name)) %>%
          httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
          httr2::req_perform()
        
        status_data <- httr2::resp_body_json(response)
        
        # 상태 추출 및 정리
        batch_state <- status_data$metadata$state %||% "UNKNOWN"
        request_count <- NA
        
        # 인라인 응답 확인으로 요청 수 계산
        if (!is.null(status_data$response) && 
            !is.null(status_data$response$inlinedResponses) &&
            !is.null(status_data$response$inlinedResponses$inlinedResponses)) {
          responses <- status_data$response$inlinedResponses$inlinedResponses
          request_count <- length(responses)
          
          # 성공 상태로 변환
          if (batch_state == "BATCH_STATE_SUCCEEDED") {
            status_data$state <- "COMPLETED"
          }
        }
        
        status_data$request_count <- request_count
        
        return(status_data)
      }, error = function(e) {
        log_message("ERROR", sprintf("배치 상태 확인 실패: %s", e$message))
        return(NULL)
      })
    },
    
    # 2. 배치 작업 상태 모니터링 (대기)
    monitor_batch_job = function(batch_name, show_progress = TRUE) {
      if (show_progress) {
        log_message("INFO", sprintf("배치 작업 모니터링 시작: %s", batch_name))
      }
      
      start_time <- Sys.time()
      max_wait_time <- BATCH_CONFIG$max_wait_hours * 3600  # 초 단위
      
      completed_states <- c("BATCH_STATE_SUCCEEDED", "BATCH_STATE_FAILED", "BATCH_STATE_CANCELLED")
      
      repeat {
        # 상태 확인
        batch_status <- self$check_batch_status(batch_name)
        
        if (is.null(batch_status)) {
          stop("배치 상태를 가져올 수 없습니다.")
        }
        
        current_state <- batch_status$metadata$state
        elapsed_time <- difftime(Sys.time(), start_time, units = "hours")
        
        if (show_progress) {
          log_message("INFO", sprintf("배치 상태: %s (경과시간: %.1f시간)", 
                                     current_state, as.numeric(elapsed_time)))
        }
        
        # 완료 상태 확인
        if (current_state %in% completed_states) {
          if (current_state == "BATCH_STATE_SUCCEEDED") {
            if (show_progress) {
              log_message("INFO", "✅ 배치 작업이 성공적으로 완료되었습니다!")
            }
            return(batch_status)
          } else if (current_state == "BATCH_STATE_FAILED") {
            log_message("ERROR", sprintf("❌ 배치 작업 실패: %s", 
                                        batch_status$error$message %||% "알 수 없는 오류"))
            stop("배치 작업이 실패했습니다.")
          } else {
            log_message("WARN", "⚠️ 배치 작업이 취소되었습니다.")
            stop("배치 작업이 취소되었습니다.")
          }
        }
        
        # 최대 대기 시간 확인
        if (as.numeric(elapsed_time) > BATCH_CONFIG$max_wait_hours) {
          log_message("ERROR", sprintf("최대 대기 시간(%d시간)을 초과했습니다.", 
                                      BATCH_CONFIG$max_wait_hours))
          stop("배치 작업 대기 시간 초과")
        }
        
        # 대기
        if (show_progress) {
          Sys.sleep(BATCH_CONFIG$poll_interval_seconds)
        } else {
          break  # 단순 상태 확인의 경우 대기하지 않음
        }
      }
    },
    
    # 3. 결과 다운로드 및 추출
    download_results = function(batch_status) {
      log_message("INFO", "배치 결과 다운로드 중...")
      
      # 인라인 배치 결과 처리 (주요 방식)
      if (!is.null(batch_status$response$inlinedResponses)) {
        log_message("INFO", "인라인 배치 응답 발견, 직접 파싱 진행")
        responses <- batch_status$response$inlinedResponses$inlinedResponses
        log_message("INFO", sprintf("인라인 응답 %d개 발견", length(responses)))
        return(responses)
      }
      
      # 파일 기반 결과 처리 (폴백)
      responses_file <- NULL
      
      if (!is.null(batch_status$response$responsesFile)) {
        responses_file <- batch_status$response$responsesFile
      } else if (!is.null(batch_status$response$responses_file)) {
        responses_file <- batch_status$response$responses_file
      } else if (!is.null(batch_status$metadata$outputInfo$gcsOutputDirectory)) {
        responses_file <- paste0(batch_status$metadata$outputInfo$gcsOutputDirectory, "/responses.jsonl")
      }
      
      if (is.null(responses_file) || responses_file == "") {
        stop("배치 결과를 찾을 수 없습니다. 인라인 응답도 없고 파일 경로도 없습니다.")
      }
      
      log_message("INFO", sprintf("결과 파일 경로: %s", responses_file))
      
      download_url <- sprintf("%s/download/v1beta/%s:download?alt=media", 
                             gsub("/v1beta", "", self$base_url), responses_file)
      
      # 결과 다운로드
      response <- httr2::request(download_url) %>%
        httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
        httr2::req_perform()
      
      # JSONL 형식 결과 파싱
      result_lines <- strsplit(httr2::resp_body_string(response), "\n")[[1]]
      result_lines <- result_lines[result_lines != ""]
      
      log_message("INFO", sprintf("배치 결과 다운로드 완료: %d개 응답", length(result_lines)))
      
      # 배치 ID에서 파일명 생성
      batch_id <- basename(responses_file)
      timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
      
      # 디스크에 원본 JSONL 저장
      raw_file_path <- file.path("results", sprintf("batch_raw_%s_%s.jsonl", batch_id, timestamp))
      if (!dir.exists("results")) {
        dir.create("results", recursive = TRUE)
      }
      
      writeLines(result_lines, raw_file_path)
      log_message("INFO", sprintf("원본 JSONL 저장: %s", raw_file_path))
      
      # 각 라인을 JSON으로 파싱
      results <- vector("list", length(result_lines))
      for (i in seq_along(result_lines)) {
        results[[i]] <- jsonlite::fromJSON(result_lines[i])
      }
      
      # 파싱된 결과도 RDS로 저장
      parsed_file_path <- file.path("results", sprintf("batch_parsed_%s_%s.RDS", batch_id, timestamp))
      saveRDS(results, parsed_file_path)
      log_message("INFO", sprintf("파싱된 결과 저장: %s", parsed_file_path))
      
      return(results)
    },
    
    # 4. 결과를 데이터프레임으로 변환 및 파싱
    parse_batch_results = function(results, original_data) {
      log_message("INFO", "배치 결과 파싱 중...")
      
      parsed_results <- vector("list", length(results))
      
      for (i in seq_along(results)) {
        result_item <- results[[i]]
        
        # 메타데이터 기반 매칭을 위한 key 파싱
        request_key <- result_item$key %||% result_item$metadata$key %||% paste0("request-", i)
        
        # key에서 메타데이터 추출
        if (startsWith(request_key, "doc_")) {
          # doc_id 기반 매칭
          doc_id <- gsub("^doc_", "", request_key)
          match_info <- list(type = "doc_id", value = doc_id)
        } else if (grepl("^post_\\d+_comment_\\d+$", request_key)) {
          # post_id, comment_id 기반 매칭
          parts <- strsplit(request_key, "_")[[1]]
          post_id <- as.numeric(parts[2])
          comment_id <- as.numeric(parts[4])
          match_info <- list(type = "post_comment", post_id = post_id, comment_id = comment_id)
        } else {
          # 순서 기반 폴백
          row_index <- as.numeric(gsub("request-", "", request_key))
          match_info <- list(type = "row_index", value = row_index)
        }
        
        # 배치 응답 구조 확인: result_item$response가 실제 API 응답
        if (is.null(result_item$response) || is.null(result_item$response$candidates)) {
          # 오류 케이스
          error_msg <- result_item$error$message %||% result_item$response$error$message %||% "알 수 없는 오류"
          # 오류 결과에 매칭 정보 포함
          error_result <- list(
            match_info = match_info,
            combinated_emotion = "API 오류",
            rationale = error_msg,
            기쁨 = NA, 신뢰 = NA, 공포 = NA, 놀람 = NA,
            슬픔 = NA, 혐오 = NA, 분노 = NA, 기대 = NA,
            P = NA, A = NA, D = NA,
            complex_emotion = NA,
            error_message = error_msg
          )
          parsed_results[[i]] <- error_result
        } else {
          # 성공 케이스 - JSON 응답 파싱
          # 배치 응답 구조: result_item$response$candidates[[1]]$content$parts[[1]]$text
          tryCatch({
            candidates <- result_item$response$candidates
            if (length(candidates) > 0 && !is.null(candidates[[1]]$content$parts)) {
              parts <- candidates[[1]]$content$parts
              if (length(parts) > 0 && !is.null(parts[[1]]$text)) {
                response_text <- parts[[1]]$text
                
                emotion_result <- self$parse_emotion_json(response_text)
                emotion_result$match_info <- match_info
                parsed_results[[i]] <- emotion_result
              } else {
                stop("응답에서 텍스트를 찾을 수 없습니다")
              }
            } else {
              stop("응답에서 candidates를 찾을 수 없습니다")
            }
          }, error = function(e) {
            # 파싱 오류 결과에 매칭 정보 포함
            parsing_error_result <- list(
              match_info = match_info,
              combinated_emotion = "파싱 오류",
              rationale = sprintf("JSON 파싱 실패: %s", e$message),
              기쁨 = NA, 신뢰 = NA, 공포 = NA, 놀람 = NA,
              슬픔 = NA, 혐오 = NA, 분노 = NA, 기대 = NA,
              P = NA, A = NA, D = NA,
              complex_emotion = NA,
              error_message = sprintf("파싱 오류: %s", e$message)
            )
            parsed_results[[i]] <- parsing_error_result
          })
        }
      }
      
      # 메타데이터 기반 매칭을 위한 데이터 준비
      final_df <- original_data
      
      # 각 결과를 메타데이터 기반으로 매칭하여 원본 데이터에 결합
      for (i in seq_along(parsed_results)) {
        result <- parsed_results[[i]]
        match_info <- result$match_info
        
        # match_info에서 매칭 정보 제거 (결과에는 포함하지 않음)
        result$match_info <- NULL
        
        # 매칭 대상 행 찾기
        if (match_info$type == "doc_id" && "doc_id" %in% names(final_df)) {
          target_rows <- which(final_df$doc_id == match_info$value)
        } else if (match_info$type == "post_comment" && all(c("post_id", "comment_id") %in% names(final_df))) {
          target_rows <- which(final_df$post_id == match_info$post_id & final_df$comment_id == match_info$comment_id)
        } else if (match_info$type == "row_index") {
          target_rows <- match_info$value
          if (target_rows > nrow(final_df)) target_rows <- integer(0)
        } else {
          # 매칭 실패 시 건너뛰기
          log_message("WARN", sprintf("매칭 실패: %s", jsonlite::toJSON(match_info)))
          next
        }
        
        # 매칭된 행에 결과 추가
        if (length(target_rows) > 0) {
          for (col_name in names(result)) {
            if (col_name %in% names(final_df)) {
              final_df[target_rows, col_name] <- result[[col_name]]
            } else {
              # 새 컬럼 추가
              final_df[[col_name]] <- NA
              final_df[target_rows, col_name] <- result[[col_name]]
            }
          }
        }
      }
      
      # 분석되지 않은 행에 기본값 설정
      if (!"combinated_emotion" %in% names(final_df)) {
        final_df$combinated_emotion <- "처리 안됨"
      } else {
        final_df$combinated_emotion[is.na(final_df$combinated_emotion)] <- "처리 안됨"
      }
      
      log_message("INFO", sprintf("결과 파싱 완료: %d행", nrow(final_df)))
      return(final_df)
    },
    
    # 5. JSON 파싱 함수 (일반 분석과 동일한 결과 구조 생성)
    parse_emotion_json = function(json_text) {
      # libs/functions.R의 parse_emotion_json_internal과 동일한 로직 사용
      return(parse_emotion_json_internal(json_text))
    },
    
    # 6. 완전한 배치 처리 (다운로드 + 파싱 + 저장)
    process_completed_batch = function(batch_name, mode_info = NULL) {
      log_message("INFO", sprintf("=== 배치 처리 시작: %s ===", batch_name))
      
      # 배치 상태 확인
      batch_status <- self$check_batch_status(batch_name)
      
      if (is.null(batch_status)) {
        stop("배치 상태를 가져올 수 없습니다.")
      }
      
      current_state <- batch_status$metadata$state
      
      if (current_state != "BATCH_STATE_SUCCEEDED") {
        cat(sprintf("⚠️ 배치 작업이 완료되지 않았습니다. 현재 상태: %s\n", current_state))
        
        if (current_state %in% c("BATCH_STATE_IN_PROGRESS", "BATCH_STATE_PENDING")) {
          cat("🔄 모니터링을 시작하시겠습니까? (y/n): ")
          choice <- tolower(trimws(readline()))
          
          if (choice == "y" || choice == "yes" || choice == "") {
            batch_status <- self$monitor_batch_job(batch_name)
          } else {
            cat("👋 모니터링을 취소합니다.\n")
            return(NULL)
          }
        } else {
          stop(sprintf("배치 작업이 실패했거나 취소되었습니다: %s", current_state))
        }
      }
      
      # 원본 데이터 로드 (05 스크립트에서 사용한 원본 데이터 재생성)
      # prompts_ready.RDS에서 데이터 로드
      if (file.exists(PATHS$prompts_data)) {
        full_corpus_with_prompts <- readRDS(PATHS$prompts_data)
        
        # 모드별 샘플링 (05 스크립트와 동일한 로직)
        if (is.null(mode_info)) {
          # 배치 이름에서 모드 추정
          if (grepl("code_check", batch_name, ignore.case = TRUE)) {
            selected_mode <- "code_check"
          } else if (grepl("pilot", batch_name, ignore.case = TRUE)) {
            selected_mode <- "pilot"
          } else if (grepl("sampling", batch_name, ignore.case = TRUE)) {
            selected_mode <- "sampling"
          } else if (grepl("full", batch_name, ignore.case = TRUE)) {
            selected_mode <- "full"
          } else {
            selected_mode <- "batch_unknown"
          }
        } else {
          selected_mode <- mode_info
        }
        
        # 동일한 샘플링 로직 사용
        if (selected_mode %in% c("code_check", "pilot", "sampling", "full")) {
          raw_sample <- get_sample_for_mode(full_corpus_with_prompts, selected_mode)
        } else {
          # 결과 개수만큼 빈 원본 데이터 생성 (나중에 results 길이에 맞춰 조정)
          raw_sample <- data.frame(
            doc_id = character(0),
            content = character(0),
            prompt = character(0),
            구분 = character(0),
            stringsAsFactors = FALSE
          )
        }
        
        # 기분석 데이터 필터링 (05 스크립트와 동일)
        data_to_process <- tracker$filter_unanalyzed(
          raw_sample,
          exclude_types = c("batch", "sample", "test", "full", "adaptive_sample"),
          model_filter = BATCH_CONFIG$model_name,
          days_back = 30
        )
        
        # 분석 제외 대상 필터링
        original_data <- data_to_process %>%
          mutate(content_cleaned = trimws(content)) %>%
          filter(
            !(is.na(content_cleaned) | content_cleaned == "" |
              content_cleaned %in% c("내용 없음", "삭제된 댓글입니다.", "비밀 댓글입니다.") |
              str_detect(content_cleaned, "작성자가 (댓글|글)을 삭제하였습니다") |
              str_length(content_cleaned) <= 2 |
              !str_detect(content_cleaned, "[가-힣A-Za-z]"))
          ) %>%
          select(-content_cleaned)
          
      } else {
        # 폴백: 빈 원본 데이터 (나중에 results에 맞춰 생성)
        original_data <- data.frame(
          doc_id = character(0),
          content = character(0),
          prompt = character(0),
          구분 = character(0),
          stringsAsFactors = FALSE
        )
      }
      
      # 결과 다운로드
      results <- self$download_results(batch_status)
      
      # 원본 데이터를 실제 배치 결과 개수에 맞춰 조정
      if (nrow(original_data) != length(results)) {
        if (nrow(original_data) > length(results)) {
          # 원본 데이터가 더 많으면 결과 개수에 맞춰 제한
          log_message("INFO", sprintf("원본 데이터를 %d건에서 %d건으로 제한합니다", 
                                     nrow(original_data), length(results)))
          original_data <- original_data[1:length(results), ]
        } else if (nrow(original_data) < length(results)) {
          # 원본 데이터가 부족하면 빈 데이터로 채움
          log_message("INFO", sprintf("원본 데이터를 %d건에서 %d건으로 확장합니다", 
                                     nrow(original_data), length(results)))
          additional_rows <- length(results) - nrow(original_data)
          
          # 원본 데이터와 동일한 컬럼 구조 유지
          if (nrow(original_data) > 0) {
            # 기존 데이터 구조를 복사하여 빈 행 생성
            template_row <- original_data[1, ]
            additional_data <- template_row[rep(1, additional_rows), ]
            
            # 기본값 설정
            additional_data$doc_id <- paste0("batch_", gsub("batches/", "", batch_name), "_", 
                                            (nrow(original_data)+1):length(results))
            additional_data$content <- ""
            additional_data$prompt <- ""
            additional_data$구분 <- "배치처리"
            additional_data$post_id <- NA
            additional_data$comment_id <- NA
          } else {
            # 완전히 빈 경우 최소 구조 생성
            additional_data <- data.frame(
              doc_id = paste0("batch_", gsub("batches/", "", batch_name), "_", 1:additional_rows),
              post_id = rep(NA, additional_rows),
              comment_id = rep(NA, additional_rows),
              content = rep("", additional_rows),
              prompt = rep("", additional_rows),
              구분 = rep("배치처리", additional_rows),
              stringsAsFactors = FALSE
            )
          }
          
          original_data <- rbind(original_data, additional_data)
        }
      }
      
      # 결과 파싱
      final_df <- self$parse_batch_results(results, original_data)
      
      # 파일명 생성 및 결과 저장
      data_count <- nrow(final_df)
      rds_filename <- generate_filepath(selected_mode, data_count, ".RDS", is_batch = TRUE)
      csv_filename <- generate_filepath(selected_mode, data_count, ".csv", is_batch = TRUE)
      
      saveRDS(final_df, rds_filename)
      readr::write_excel_csv(final_df, csv_filename, na = "")
      
      # 분석 이력 등록 (유효한 결과만)
      valid_results <- final_df %>% 
        filter(
          !is.na(combinated_emotion) & 
          combinated_emotion != "API 오류" & 
          combinated_emotion != "파싱 오류"
        )
      
      if (nrow(valid_results) > 0) {
        tracker$register_analysis(
          valid_results,
          analysis_type = paste0("batch_", selected_mode),
          model_used = BATCH_CONFIG$model_name,
          analysis_file = "06_배치모니터_결과처리"
        )
      } else {
        log_message("WARN", "유효한 분석 결과가 없어 이력 등록을 생략합니다.")
      }
      
      # 완료 메시지
      cat("\n", rep("=", 70), "\n")
      cat("🎉 배치 결과 처리가 완료되었습니다!\n")
      cat(sprintf("📊 처리된 데이터: %d건\n", data_count))
      cat(sprintf("💾 RDS 파일: %s\n", basename(rds_filename)))
      cat(sprintf("💾 CSV 파일: %s\n", basename(csv_filename)))
      cat(rep("=", 70), "\n")
      
      log_message("INFO", sprintf("배치 처리 완료: %s", basename(rds_filename)))
      log_message("INFO", "=== 배치 처리 종료 ===")
      
      return(final_df)
    },
    
    # 저장된 배치 결과 파일 목록 조회
    list_saved_batch_files = function() {
      results_dir <- "results"
      if (!dir.exists(results_dir)) {
        log_message("WARNING", "results 디렉토리가 존재하지 않습니다")
        return(data.frame())
      }
      
      # 배치 결과 파일들 찾기
      raw_files <- list.files(results_dir, pattern = "^batch_raw_.*\\.jsonl$", full.names = TRUE)
      parsed_files <- list.files(results_dir, pattern = "^batch_parsed_.*\\.RDS$", full.names = TRUE)
      
      # 파일 정보 생성
      file_info <- data.frame(
        raw_file = raw_files,
        parsed_file = parsed_files,
        batch_id = sub("^batch_raw_(.*?)_\\d{8}_\\d{6}\\.jsonl$", "\\1", basename(raw_files)),
        timestamp = sub("^batch_raw_.*_(\\d{8}_\\d{6})\\.jsonl$", "\\1", basename(raw_files)),
        stringsAsFactors = FALSE
      )
      
      return(file_info)
    },
    
    # 저장된 배치 결과 로드
    load_saved_batch_results = function(batch_id = NULL, timestamp = NULL, file_path = NULL) {
      if (!is.null(file_path)) {
        # 직접 파일 경로 지정된 경우
        if (grepl("\\.jsonl$", file_path)) {
          # JSONL 파일에서 로드
          log_message("INFO", sprintf("JSONL 파일에서 결과 로드: %s", file_path))
          result_lines <- readLines(file_path)
          results <- vector("list", length(result_lines))
          for (i in seq_along(result_lines)) {
            results[[i]] <- jsonlite::fromJSON(result_lines[i])
          }
          return(results)
        } else if (grepl("\\.RDS$", file_path)) {
          # RDS 파일에서 로드
          log_message("INFO", sprintf("RDS 파일에서 결과 로드: %s", file_path))
          return(readRDS(file_path))
        } else {
          stop("지원하지 않는 파일 형식입니다. .jsonl 또는 .RDS 파일만 지원합니다.")
        }
      }
      
      # 배치 ID와 타임스탬프로 파일 찾기
      file_info <- self$list_saved_batch_files()
      
      if (nrow(file_info) == 0) {
        stop("저장된 배치 결과 파일이 없습니다")
      }
      
      # 필터링
      if (!is.null(batch_id)) {
        file_info <- file_info[file_info$batch_id == batch_id, ]
      }
      
      if (!is.null(timestamp)) {
        file_info <- file_info[file_info$timestamp == timestamp, ]
      }
      
      if (nrow(file_info) == 0) {
        stop(sprintf("조건에 맞는 배치 결과 파일을 찾을 수 없습니다 (batch_id: %s, timestamp: %s)", batch_id %||% "전체", timestamp %||% "전체"))
      }
      
      # 가장 최근 파일 선택
      latest_file <- file_info[order(file_info$timestamp, decreasing = TRUE)[1], ]
      
      log_message("INFO", sprintf("배치 결과 로드: %s", latest_file$parsed_file))
      return(readRDS(latest_file$parsed_file))
    }
  )
)

# 배치 작업 목록 읽기 함수
read_batch_jobs <- function() {
  batch_info_file <- file.path(PATHS$results_dir, "current_batch_jobs.txt")
  
  if (!file.exists(batch_info_file)) {
    cat("📋 현재 등록된 배치 작업이 없습니다.\n")
    cat("💡 먼저 05_batch_request.R 스크립트로 배치 요청을 제출하세요.\n")
    return(NULL)
  }
  
  batch_lines <- readLines(batch_info_file, warn = FALSE)
  batch_lines <- batch_lines[batch_lines != "" & !grepl("^===", batch_lines)]
  
  if (length(batch_lines) == 0) {
    cat("📋 등록된 배치 작업이 없습니다.\n")
    return(NULL)
  }
  
  # 배치 작업 정보 파싱
  batch_info <- vector("list", length(batch_lines))
  
  for (i in seq_along(batch_lines)) {
    line <- batch_lines[i]
    
    # 패턴: [시간] 배치명 - 모드 (건수)
    if (grepl("\\[.*\\]\\s+(\\S+)\\s+-\\s+(\\w+)\\s+모드\\s+\\((\\d+)건\\)", line)) {
      matches <- regmatches(line, regexec("\\[(.*)\\]\\s+(\\S+)\\s+-\\s+(\\w+)\\s+모드\\s+\\((\\d+)건\\)", line))[[1]]
      
      if (length(matches) >= 5) {
        batch_info[[i]] <- list(
          timestamp = matches[2],
          batch_name = matches[3],
          mode = matches[4],
          count = as.numeric(matches[5]),
          full_line = line
        )
      }
    }
  }
  
  # NULL 항목 제거
  batch_info <- batch_info[!sapply(batch_info, is.null)]
  
  return(batch_info)
}

# 대화형 배치 관리자
interactive_batch_manager <- function() {
  monitor <- BatchMonitor$new()
  
  while (TRUE) {
    cat("\n", rep("=", 70), "\n")
    cat("🔍 배치 작업 모니터링 및 결과 처리\n")
    cat(rep("=", 70), "\n")
    
    # 배치 작업 목록 표시
    batch_jobs <- read_batch_jobs()
    
    if (is.null(batch_jobs) || length(batch_jobs) == 0) {
      cat("\n💡 05_batch_request.R 스크립트로 배치 요청을 먼저 제출하세요.\n")
      return(NULL)
    }
    
    cat("\n📋 등록된 배치 작업 목록:\n")
    cat(rep("-", 50), "\n")
    
    # 실시간 상태 확인
    for (i in seq_along(batch_jobs)) {
      job <- batch_jobs[[i]]
      
      # 배치 상태 확인
      batch_status <- monitor$check_batch_status(job$batch_name)
      
      if (!is.null(batch_status)) {
        state_display <- switch(batch_status$metadata$state,
          "BATCH_STATE_SUCCEEDED" = "✅ 완료",
          "BATCH_STATE_IN_PROGRESS" = "🔄 진행중",
          "BATCH_STATE_PENDING" = "⏳ 대기중",
          "BATCH_STATE_FAILED" = "❌ 실패",
          "BATCH_STATE_CANCELLED" = "⚠️ 취소됨",
          "❓ 알수없음"
        )
        
        request_count_info <- if (!is.na(batch_status$request_count)) {
          sprintf(" (%d건)", batch_status$request_count)
        } else {
          sprintf(" (%d건)", job$count)
        }
        
      } else {
        state_display <- "❓ 상태확인불가"
        request_count_info <- sprintf(" (%d건)", job$count)
      }
      
      cat(sprintf("%d. [%s] %s - %s%s\n", 
                 i, state_display, job$mode, 
                 substr(job$batch_name, nchar(job$batch_name) - 15, nchar(job$batch_name)),
                 request_count_info))
    }
    
    cat(rep("-", 50), "\n")
    cat("M. 수동으로 배치명 입력\n")
    cat("R. 목록 새로고침\n")
    cat("Q. 종료\n")
    cat(rep("-", 50), "\n")
    
    choice <- readline("선택하세요: ")
    choice <- trimws(choice)
    
    if (tolower(choice) == "q") {
      cat("👋 배치 모니터를 종료합니다.\n")
      break
    } else if (tolower(choice) == "r") {
      cat("🔄 목록을 새로고침합니다...\n")
      next
    } else if (tolower(choice) == "m") {
      # 수동 배치명 입력
      batch_name <- readline("배치 작업명을 입력하세요: ")
      batch_name <- trimws(batch_name)
      
      if (batch_name == "") {
        cat("❌ 배치 작업명이 입력되지 않았습니다.\n")
        next
      }
      
      cat(sprintf("🔍 '%s' 배치 작업을 처리합니다...\n", batch_name))
      
      tryCatch({
        result <- monitor$process_completed_batch(batch_name)
        if (!is.null(result)) {
          cat("✅ 처리 완료!\n")
        }
      }, error = function(e) {
        cat("❌ 배치 처리 중 오류:", e$message, "\n")
      })
      
    } else {
      # 숫자 선택
      choice_num <- suppressWarnings(as.numeric(choice))
      
      if (is.na(choice_num) || choice_num < 1 || choice_num > length(batch_jobs)) {
        cat("❌ 잘못된 선택입니다.\n")
        next
      }
      
      selected_job <- batch_jobs[[choice_num]]
      
      cat(sprintf("🔍 선택된 배치: %s (%s 모드, %d건)\n", 
                 selected_job$batch_name, selected_job$mode, selected_job$count))
      
      tryCatch({
        # Python 또는 R 방식으로 처리
        result <- NULL
        
        # Python 배치 설정 확인 (config.R에서 로드)
        use_python_batch <- if (exists("PYTHON_CONFIG") && !is.null(PYTHON_CONFIG$use_python_batch)) {
          PYTHON_CONFIG$use_python_batch
        } else {
          FALSE  # 기본값: R 방식 사용
        }
        
        if (use_python_batch && !is.null(selected_job$method) && selected_job$method == "python") {
          # Python 배치 모니터링 시도
          result <- monitor_python_batch(selected_job$batch_name, selected_job$mode)
        } else {
          # R 배치 처리
          result <- monitor$process_completed_batch(selected_job$batch_name, selected_job$mode)
        }
        
        if (!is.null(result)) {
          cat("✅ 처리 완료!\n")
          
          # 계속할지 묻기
          cat("\n다른 배치를 처리하시겠습니까? (y/n): ")
          continue_choice <- tolower(trimws(readline()))
          
          if (continue_choice != "y" && continue_choice != "yes" && continue_choice != "") {
            cat("👋 배치 모니터를 종료합니다.\n")
            break
          }
        }
      }, error = function(e) {
        cat("❌ 배치 처리 중 오류:", e$message, "\n")
      })
    }
  }
}

# 메인 실행 함수
run_main_monitor <- function() {
  cat("🔍 배치 작업 모니터링을 시작합니다...\n")
  interactive_batch_manager()
}

# 초기화 완료 메시지
cat("\n", rep("=", 70), "\n")
cat("🎉 06_배치모니터.R 스크립트 초기화 완료!\n")
cat("📝 역할: 배치 작업 모니터링 + 다운로드 + 파싱 전담\n")
cat(rep("=", 70), "\n")

# 스크립트 실행 시 자동으로 모니터링 시작
if (!interactive()) {
  # 명령줄 모드: 바로 모니터링 시작
  cat("📟 명령줄 모드에서 배치 모니터링을 시작합니다...\n\n")
  run_main_monitor()
} else {
  # 대화형 모드: 바로 모니터링 시작
  cat("🔍 배치 모니터링을 시작합니다...\n\n")
  
  # 자동으로 모니터링 시작
  tryCatch({
    run_main_monitor()
  }, error = function(e) {
    cat("\n❌ 배치 모니터링 중 오류가 발생했습니다:\n")
    cat("오류 메시지:", e$message, "\n\n")
    cat("💡 문제 해결 방법:\n")
    cat("1. API 키 설정 확인: Sys.getenv('GEMINI_API_KEY')\n")
    cat("2. 배치 작업명 확인\n")
    cat("3. 인터넷 연결 상태 확인\n")
    cat("4. 다시 시도: run_main_monitor()\n")
  })
}