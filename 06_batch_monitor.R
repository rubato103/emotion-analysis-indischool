# Gemini API 배치 모니터링 및 결과 처리 스크립트
# 목적: 배치 작업 상태 모니터링, 완료된 데이터 다운로드 및 파싱 전담
# 특징: 05 스크립트에서 요청한 배치 작업의 후속 처리 담당

# 통합 초기화 시스템 로드
cat("📂 종속 스크립트 로드 중... ")
tryCatch({
  source("libs/init.R")
  source("libs/utils.R")
  source("modules/analysis_tracker.R")
  source("modules/adaptive_sampling.R")
  cat("✅ 완료\n")
}, error = function(e) {
  cat("❌ 실패\n")
  stop("필수 스크립트 로드 중 오류 발생: ", e$message)
})

# 필요한 패키지 로드
cat("📦 필수 패키지 로드 중... ")
required_packages <- c("dplyr", "stringr", "jsonlite", "httr2", "readr", "R6")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]

if(length(new_packages) > 0) {
  cat("▶️ 신규 패키지 설치:", paste(new_packages, collapse = ", "), "... ")
  install.packages(new_packages, dependencies = TRUE, quiet = TRUE)
}

suppressPackageStartupMessages({
  loaded <- sapply(required_packages, require, character.only = TRUE, quietly = TRUE)
})

if (all(loaded)) {
  cat("✅ 완료\n")
} else {
  cat("❌ 실패\n")
  stop("다음 패키지 로드에 실패했습니다: ", paste(required_packages[!loaded], collapse = ", "))
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
    
    # 3. 결과 다운로드 및 추출 (정돈된 출력)
    download_results = function(batch_status) {
      cat("  - 배치 결과 다운로드 중... ")
      
      # 인라인 배치 결과 처리 (주요 방식)
      if (!is.null(batch_status$response$inlinedResponses)) {
        responses <- batch_status$response$inlinedResponses$inlinedResponses
        cat(sprintf("✅ 완료 (%d개 인라인 응답)\n", length(responses)))
        log_message("DEBUG", "인라인 배치 응답 발견, 직접 파싱 진행")
        return(responses)
      }
      
      # 파일 기반 결과 처리 (폴백)
      responses_file <- batch_status$response$responsesFile %||% 
                        batch_status$response$responses_file %||% 
                        paste0(batch_status$metadata$outputInfo$gcsOutputDirectory, "/responses.jsonl")

      if (is.null(responses_file) || responses_file == "") {
        cat("❌ 실패\n")
        stop("배치 결과를 찾을 수 없습니다. 인라인 응답도 없고 파일 경로도 없습니다.")
      }
      
      log_message("DEBUG", sprintf("결과 파일 GCS 경로: %s", responses_file))
      
      download_url <- sprintf("%s/download/v1beta/%s:download?alt=media", 
                             gsub("/v1beta", "", self$base_url), responses_file)
      
      # 결과 다운로드
      response <- httr2::request(download_url) %>%
        httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
        httr2::req_perform()
      
      # JSONL 형식 결과 파싱
      result_lines <- strsplit(httr2::resp_body_string(response), "\n")[[1]]
      result_lines <- result_lines[result_lines != ""]
      cat(sprintf("✅ 완료 (%d개 응답)\n", length(result_lines)))
      
      # 원본 JSONL 저장
      cat("  - 원본 JSONL 파일 저장 중... ")
      batch_id <- basename(responses_file)
      timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
      raw_file_path <- file.path("results", sprintf("batch_raw_%s_%s.jsonl", batch_id, timestamp))
      if (!dir.exists("results")) dir.create("results", recursive = TRUE)
      
      writeLines(result_lines, raw_file_path)
      cat(sprintf("✅ 완료 (%s)\n", basename(raw_file_path)))
      
      # 각 라인을 JSON으로 파싱
      results <- lapply(result_lines, jsonlite::fromJSON)
      
      # 파싱된 중간 결과를 Parquet으로 저장 (디버깅용)
      if (BATCH_CONFIG$save_intermediate_files) {
        cat("  - 파싱된 중간 결과 저장 중... ")
        parsed_file_base <- file.path("results", sprintf("batch_parsed_%s_%s", batch_id, timestamp))
        save_parquet(results, parsed_file_base)
        cat("✅ 완료\n")
      }
      
      return(results)
    },
    
    # 4. 결과를 데이터프레임으로 변환 및 파싱 (정돈된 출력)
    parse_batch_results = function(results, original_data) {
      cat("  - 배치 결과 파싱 및 처리 중...\n")
      
      # 1. API 응답 파싱
      cat("    - API 응답 파싱... ")
      parsed_data <- lapply(seq_along(results), function(i) {
        result_item <- results[[i]]
        key <- result_item$key %||% paste0("item_", i)
        
        # 응답 텍스트 추출
        response_text <- tryCatch({
          result_item$response$candidates$content$parts[[1]]$text[1]
        }, error = function(e) { NULL })
        
        if (!is.null(response_text) && response_text != "") {
          json_text <- gsub("^```json\n?|\n?```$", "", response_text)
          tryCatch({
            emotion_data <- jsonlite::fromJSON(json_text)
            list(
              key = key,
              기쁨 = emotion_data$plutchik_emotions$기쁨 %||% NA,
              신뢰 = emotion_data$plutchik_emotions$신뢰 %||% NA,
              공포 = emotion_data$plutchik_emotions$공포 %||% NA,
              놀람 = emotion_data$plutchik_emotions$놀람 %||% NA,
              슬픔 = emotion_data$plutchik_emotions$슬픔 %||% NA,
              혐오 = emotion_data$plutchik_emotions$혐오 %||% NA,
              분노 = emotion_data$plutchik_emotions$분노 %||% NA,
              기대 = emotion_data$plutchik_emotions$기대 %||% NA,
              P = emotion_data$PAD$P %||% NA,
              A = emotion_data$PAD$A %||% NA,
              D = emotion_data$PAD$D %||% NA,
              emotion_source = emotion_data$emotion_target$source %||% NA,
              emotion_direction = emotion_data$emotion_target$direction %||% NA,
              combinated_emotion = emotion_data$combinated_emotion %||% NA,
              complex_emotion = emotion_data$complex_emotion %||% NA,
              rationale = emotion_data$rationale %||% NA,
              error_message = NA
            )
          }, error = function(e) {
            list(key = key, combinated_emotion = "파싱 오류", rationale = paste("JSON 파싱 실패:", e$message), error_message = e$message)
          })
        } else {
          list(key = key, combinated_emotion = "응답 없음", rationale = "API 응답이 없습니다", error_message = "API 응답이 없습니다")
        }
      })
      
      batch_df <- dplyr::bind_rows(parsed_data)
      cat(sprintf("✅ 완료 (%d개 결과 파싱)\n", nrow(batch_df)))
      
      if (nrow(batch_df) == 0) return(data.frame())

      # 2. ID 정보 추출
      cat("    - ID 정보 추출... ")
      key_parts <- strsplit(batch_df$key, "_")
      batch_df$post_id <- as.numeric(sapply(key_parts, function(p) if(length(p) >= 2) p[2] else NA))
      batch_df$comment_id <- as.numeric(sapply(key_parts, function(p) if(length(p) >= 4) p[4] else NA))
      cat(sprintf("✅ 완료 (%d개 ID 추출)\n", sum(!is.na(batch_df$post_id))))

      # 3. 원본 데이터와 결합
      cat("    - 원본 데이터와 결합... ")
      base_path <- PATHS$prompts_data
      possible_files <- paste0(base_path, c(".parquet", ".RDS"))
      existing_file <- possible_files[file.exists(possible_files)][1]

      if (is.na(existing_file)) {
        cat("❌ 실패\n")
        log_message("WARN", sprintf("원본 데이터 파일을 찾을 수 없습니다. 확인된 경로: %s", paste(possible_files, collapse=", ")))
        return(data.frame())
      }
      
      full_original_data <- load_prompts_data()
      if (is.null(full_original_data)) {
        cat("❌ 실패\n")
        log_message("ERROR", "원본 데이터 로드에 실패했습니다.")
        return(data.frame())
      }

      matched_df <- dplyr::semi_join(full_original_data, batch_df, by = c("post_id", "comment_id")) %>%
                    dplyr::left_join(batch_df, by = c("post_id", "comment_id"))
      cat(sprintf("✅ 완료 (%d개 데이터 결합)\n", nrow(matched_df)))

      if (nrow(matched_df) == 0) {
        log_message("WARN", "매칭된 데이터가 없습니다. 데이터 구조를 확인하세요.")
        return(data.frame())
      }

      # 4. 최종 데이터 구조 정리
      cat("    - 최종 데이터 구조 정리... ")
      regular_columns <- c("post_id", "comment_id", "page_url", "depth", "구분", "title", "author", "date", "views", "likes", "content", "prompt", "chunk_id", "기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대", "P", "A", "D", "emotion_source", "emotion_direction", "combinated_emotion", "complex_emotion", "rationale", "error_message")
      
      final_df <- matched_df
      if (!"chunk_id" %in% names(final_df)) final_df$chunk_id <- 1
      
      # 모든 정규 컬럼이 존재하도록 보장
      for (col in regular_columns) {
        if (!col %in% names(final_df)) {
          final_df[[col]] <- NA
        }
      }
      
      final_df <- final_df[, regular_columns]
      cat("✅ 완료\n")
      
      log_message("INFO", sprintf("결과 파싱 및 처리 완료: 최종 %d건", nrow(final_df)))
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
      
      # 모드 결정 로직 (개선된 버전)
      if (is.null(mode_info)) {
        # 배치 이름에서 모드 추정 (개선된 로직)
        selected_mode <- "batch_unknown"
        
        # 배치 이름에 모드가 직접 포함된 경우
        if (grepl("code_check", batch_name, ignore.case = TRUE)) {
          selected_mode <- "code_check"
        } else if (grepl("pilot", batch_name, ignore.case = TRUE)) {
          selected_mode <- "pilot"
        } else if (grepl("sampling", batch_name, ignore.case = TRUE)) {
          selected_mode <- "sampling"
        } else if (grepl("full", batch_name, ignore.case = TRUE)) {
          selected_mode <- "full"
        } else {
          # 배치 작업 목록에서 모드 정보 추출
          batch_jobs <- read_batch_jobs()
          if (!is.null(batch_jobs)) {
            for (job in batch_jobs) {
              if (grepl(batch_name, job$batch_name, fixed = TRUE) || 
                  grepl(job$batch_name, batch_name, fixed = TRUE)) {
                selected_mode <- job$mode
                break
              }
            }
          }
          
          # 여전히 모드를 결정할 수 없는 경우 기본값 설정
          if (selected_mode == "batch_unknown") {
            selected_mode <- "code_check"  # 기본값으로 code_check 사용
            log_message("INFO", "모드를 결정할 수 없어 기본값(code_check) 사용")
          }
        }
      } else {
        selected_mode <- mode_info
      }
      
      # 결과 다운로드
      results <- self$download_results(batch_status)
      
      # 결과 파싱 (integrate_batch_results.R 방식 사용 - 원데이터는 parse_batch_results에서 직접 로드)
      final_df <- self$parse_batch_results(results, NULL)
      
      # 결과가 비어 있는지 확인
      if (nrow(final_df) == 0) {
        log_message("WARN", "파싱된 결과가 없습니다")
        # 빈 데이터 프레임을 적절한 구조로 생성
        final_df <- data.frame(
          post_id = numeric(0),
          comment_id = numeric(0),
          page_url = character(0),
          depth = numeric(0),
          구분 = character(0),
          title = character(0),
          author = character(0),
          date = character(0),
          views = numeric(0),
          likes = numeric(0),
          content = character(0),
          prompt = character(0),
          chunk_id = numeric(0),
          기쁨 = numeric(0),
          신뢰 = numeric(0),
          공포 = numeric(0),
          놀람 = numeric(0),
          슬픔 = numeric(0),
          혐오 = numeric(0),
          분노 = numeric(0),
          기대 = numeric(0),
          P = numeric(0),
          A = numeric(0),
          D = numeric(0),
          emotion_source = character(0),
          emotion_direction = character(0),
          combinated_emotion = character(0),
          complex_emotion = character(0),
          rationale = character(0),
          error_message = character(0),
          stringsAsFactors = FALSE
        )
      }
      
      # 파일명 생성 및 결과 저장
      data_count <- nrow(final_df)
      # 일반 분석 결과와 동일한 구조로 저장
      result_filename <- generate_filepath(selected_mode, data_count, ".parquet", is_batch = TRUE)
      
      # Parquet으로 저장
      save_parquet(final_df, gsub("\\.parquet$", "", result_filename))

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
      cat(sprintf("💾 Parquet 파일: %s\n", basename(result_filename)))
      
      cat(rep("=", 70), "\n")
      
      log_message("INFO", sprintf("배치 처리 완료: %s", basename(result_filename)))
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
      # Parquet 파일과 RDS 파일 모두 찾기
      parsed_files_rds <- list.files(results_dir, pattern = "^batch_parsed_.*\\.RDS$", full.names = TRUE)
      parsed_files_parquet <- list.files(results_dir, pattern = "^batch_parsed_.*\\.parquet$", full.names = TRUE)
      parsed_files <- c(parsed_files_rds, parsed_files_parquet)
      
      # 파일 정보 생성
      # raw_files와 parsed_files의 개수가 맞지 않을 수 있으므로 각각 처리
      raw_count <- length(raw_files)
      parsed_count <- length(parsed_files)
      
      # 더 많은 파일 수에 맞춰 처리
      max_count <- max(raw_count, parsed_count)
      
      # 확장자를 제거한 파일명 생성
      raw_names <- if (raw_count > 0) {
        sub("^batch_raw_(.*?)_\\d{8}_\\d{6}\\.jsonl$", "\\1", basename(raw_files))
      } else {
        character(0)
      }
      
      timestamps <- if (raw_count > 0) {
        sub("^batch_raw_.*_(\\d{8}_\\d{6})\\.jsonl$", "\\1", basename(raw_files))
      } else {
        character(0)
      }
      
      # 파일 정보 생성
      file_info <- data.frame(
        raw_file = if (raw_count > 0) raw_files else character(max_count),
        parsed_file = if (parsed_count > 0) parsed_files else character(max_count),
        batch_id = if (raw_count > 0) raw_names else character(max_count),
        timestamp = if (raw_count > 0) timestamps else character(max_count),
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
          return(load_parquet(gsub("\\.RDS$", "", file_path)))
        } else if (grepl("\\.parquet$", file_path)) {
          # Parquet 파일에서 로드
          log_message("INFO", sprintf("Parquet 파일에서 결과 로드: %s", file_path))
          return(load_parquet(gsub("\\.parquet$", "", file_path)))
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
      return(load_parquet(gsub("\\.RDS$", "", latest_file$parsed_file)))
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