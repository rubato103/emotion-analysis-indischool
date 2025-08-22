# Gemini API 배치 처리 감정분석 스크립트
# 목적: 대량 데이터를 할인된 비용으로 배치 처리하여 감정분석 수행 
# 특징: 비동기 방식, 대용량 처리 최적화 (config.R에서 할인율과 처리시간 설정)

# 설정 및 유틸리티 로드 (오류 처리 포함)
cat("📂 종속 파일 로드 중...\n")

tryCatch({
  source("config.R")
  cat("✅ config.R 로드 완료\n")
}, error = function(e) {
  stop("❌ config.R 로드 실패: ", e$message)
})

tryCatch({
  source("utils.R")
  cat("✅ utils.R 로드 완료\n")
}, error = function(e) {
  stop("❌ utils.R 로드 실패: ", e$message)
})

tryCatch({
  source("analysis_tracker.R")
  cat("✅ analysis_tracker.R 로드 완료\n")
}, error = function(e) {
  stop("❌ analysis_tracker.R 로드 실패: ", e$message)
})

tryCatch({
  source("adaptive_sampling.R")
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
# BATCH_CONFIG 사용
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
  cat("💡 설정 방법: Sys.setenv(GEMINI_API_KEY = 'your-api-key')\n")
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

# 배치 처리 관리자 클래스
BatchProcessor <- R6Class("BatchProcessor",
  public = list(
    api_key = NULL,
    base_url = "https://generativelanguage.googleapis.com/v1beta",
    
    initialize = function() {
      self$api_key <- Sys.getenv("GEMINI_API_KEY")
      if (self$api_key == "") {
        stop("⚠️ Gemini API 키가 설정되지 않았습니다.")
      }
      log_message("INFO", "배치 프로세서 초기화 완료")
    },
    
    # 1. 배치 요청 파일 생성 (JSONL 형식)
    create_batch_file = function(data, file_path) {
      if (BATCH_CONFIG$detailed_logging) {
        log_message("INFO", sprintf("배치 파일 생성 시작: %d개 요청 (모델: %s)", 
                                   nrow(data), BATCH_CONFIG$model_name))
      } else {
        log_message("INFO", sprintf("배치 파일 생성 시작: %d개 요청", nrow(data)))
      }
      
      # JSONL 파일 생성 - 각 라인은 완전한 GenerateContentRequest
      jsonl_lines <- vector("character", nrow(data))
      
      for (i in seq_len(nrow(data))) {
        # 정확한 JSONL 배치 요청 형식 (사용자 예제 기반)
        request_obj <- list(
          contents = list(
            list(
              parts = list(
                list(text = data$prompt[i])
              )
            )
          ),
          generation_config = list(
            temperature = as.numeric(BATCH_CONFIG$temperature %||% 0.25),
            topP = as.numeric(BATCH_CONFIG$top_p %||% 0.85)
          )
        )
        
        # JSONL 라인 형식 (key + request)
        batch_item <- list(
          key = sprintf("request-%d", i),
          request = request_obj
        )
        
        jsonl_lines[i] <- jsonlite::toJSON(batch_item, auto_unbox = TRUE)
      }
      
      # JSONL 파일 작성
      writeLines(jsonl_lines, file_path, useBytes = TRUE)
      
      # 파일 크기 확인
      file_size_mb <- file.size(file_path) / (1024^2)
      log_message("INFO", sprintf("배치 파일 생성 완료: %.2f MB", file_size_mb))
      
      if (file_size_mb > BATCH_CONFIG$max_file_size_mb) {
        stop(sprintf("파일 크기(%.2f MB)가 제한(%.0f MB)을 초과합니다.", 
                    file_size_mb, BATCH_CONFIG$max_file_size_mb))
      }
      
      return(file_path)
    },
    
    # 2. 파일 업로드 (Resumable Upload)
    upload_file = function(file_path) {
      log_message("INFO", "파일 업로드 시작...")
      
      # 파일 정보
      file_size <- file.size(file_path)
      mime_type <- "application/jsonl"
      display_name <- sprintf("batch_input_%s", format(Sys.time(), "%Y%m%d_%H%M%S"))
      
      # 1단계: Resumable upload 시작
      upload_base_url <- "https://generativelanguage.googleapis.com"
      start_response <- httr2::request(sprintf("%s/upload/v1beta/files", upload_base_url)) %>%
        httr2::req_headers(
          `x-goog-api-key` = self$api_key,
          `X-Goog-Upload-Protocol` = "resumable",
          `X-Goog-Upload-Command` = "start",
          `X-Goog-Upload-Header-Content-Length` = as.character(file_size),
          `X-Goog-Upload-Header-Content-Type` = mime_type,
          `Content-Type` = "application/json"
        ) %>%
        httr2::req_body_json(list(
          file = list(display_name = display_name)
        )) %>%
        httr2::req_perform()
      
      # Upload URL 추출
      upload_url <- httr2::resp_headers(start_response)[["x-goog-upload-url"]]
      if (is.null(upload_url)) {
        stop("업로드 URL을 가져올 수 없습니다.")
      }
      
      # 2단계: 실제 파일 업로드
      file_content <- readBin(file_path, "raw", file_size)
      
      upload_response <- httr2::request(upload_url) %>%
        httr2::req_headers(
          `Content-Length` = as.character(file_size),
          `X-Goog-Upload-Offset` = "0",
          `X-Goog-Upload-Command` = "upload, finalize"
        ) %>%
        httr2::req_body_raw(file_content) %>%
        httr2::req_perform()
      
      upload_result <- httr2::resp_body_json(upload_response)
      file_uri <- upload_result$file$uri  # URI 사용
      
      log_message("INFO", sprintf("파일 업로드 완료: %s", file_uri))
      return(file_uri)
    },
    
    # 3. 배치 작업 생성 (인라인 방식)
    create_batch_job = function(file_uri, batch_file) {
      log_message("INFO", "배치 작업 생성 중...")
      
      # 인라인 방식으로 대체 (테스트 파일 참조)
      # 파일 내용을 읽어서 인라인 요청으로 변환
      file_content <- readLines(batch_file, warn = FALSE)
      inline_requests <- vector("list", length(file_content))
      
      for (i in seq_along(file_content)) {
        if (file_content[i] != "") {
          line_data <- jsonlite::fromJSON(file_content[i])
          inline_requests[[i]] <- list(
            request = line_data$request,
            metadata = list(key = line_data$key)
          )
        }
      }
      
      # 올바른 배치 요청 구조 (테스트 파일 기반)
      batch_request <- list(
        batch = list(
          display_name = sprintf("emotion_batch_%s", format(Sys.time(), "%Y%m%d_%H%M%S")),
          input_config = list(
            requests = list(
              requests = inline_requests
            )
          )
        )
      )
      
      tryCatch({
        # 정확한 배치 엔드포인트
        batch_endpoint <- sprintf("%s/models/%s:batchGenerateContent", 
                                 self$base_url, BATCH_CONFIG$model_name)
        
        response <- httr2::request(batch_endpoint) %>%
          httr2::req_headers(
            `x-goog-api-key` = self$api_key,
            `Content-Type` = "application/json"
          ) %>%
          httr2::req_method("POST") %>%
          httr2::req_body_json(batch_request) %>%
          httr2::req_perform()
        
        batch_result <- httr2::resp_body_json(response)
        operation_name <- batch_result$name
        
        log_message("INFO", sprintf("배치 작업 생성 완료: %s", operation_name))
        return(operation_name)
        
      }, error = function(e) {
        log_message("ERROR", sprintf("배치 작업 생성 실패: %s", e$message))
        
        # 에러 상세 정보 추출 (향상된 디버깅)
        tryCatch({
          if (inherits(e, "httr2_http_400")) {
            error_body <- httr2::resp_body_string(e$resp)
            log_message("ERROR", sprintf("HTTP 400 응답 내용: %s", error_body))
            
            # JSON 파싱 시도
            error_json <- jsonlite::fromJSON(error_body, simplifyVector = FALSE)
            if (!is.null(error_json$error)) {
              log_message("ERROR", sprintf("에러 메시지: %s", error_json$error$message))
              if (!is.null(error_json$error$details)) {
                log_message("ERROR", sprintf("에러 상세: %s", jsonlite::toJSON(error_json$error$details, auto_unbox = TRUE)))
              }
            }
          }
        }, error = function(e2) {
          log_message("WARN", "에러 응답을 파싱할 수 없습니다.")
        })
        
        stop(sprintf("배치 작업 생성에 실패했습니다: %s", e$message))
      })
    },
    
    # 4. 배치 작업 상태 모니터링
    monitor_batch_job = function(batch_name) {
      log_message("INFO", sprintf("배치 작업 모니터링 시작: %s", batch_name))
      
      start_time <- Sys.time()
      max_wait_time <- BATCH_CONFIG$max_wait_hours * 3600  # 초 단위
      
      completed_states <- c("BATCH_STATE_SUCCEEDED", "BATCH_STATE_FAILED", "BATCH_STATE_CANCELLED")
      
      repeat {
        # 상태 확인
        response <- httr2::request(sprintf("%s/%s", self$base_url, batch_name)) %>%
          httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
          httr2::req_perform()
        
        batch_status <- httr2::resp_body_json(response)
        current_state <- batch_status$metadata$state
        
        elapsed_time <- difftime(Sys.time(), start_time, units = "hours")
        log_message("INFO", sprintf("배치 상태: %s (경과시간: %.1f시간)", 
                                   current_state, as.numeric(elapsed_time)))
        
        # 완료 상태 확인
        if (current_state %in% completed_states) {
          if (current_state == "BATCH_STATE_SUCCEEDED") {
            log_message("INFO", "✅ 배치 작업이 성공적으로 완료되었습니다!")
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
        Sys.sleep(BATCH_CONFIG$poll_interval_seconds)
      }
    },
    
    # 5. 결과 다운로드 및 파싱
    download_results = function(batch_status) {
      log_message("INFO", "배치 결과 다운로드 중...")
      
      # 배치 상태 구조 디버깅
      log_message("INFO", sprintf("배치 상태 구조 확인: %s", jsonlite::toJSON(batch_status, auto_unbox = TRUE)))
      
      # 결과 파일 URI 추출 (여러 경로 시도) 
      responses_file <- NULL
      
      # 가능한 경로들 시도
      if (!is.null(batch_status$response$responsesFile)) {
        responses_file <- batch_status$response$responsesFile
      } else if (!is.null(batch_status$response$responses_file)) {
        responses_file <- batch_status$response$responses_file
      } else if (!is.null(batch_status$metadata$outputInfo$gcsOutputDirectory)) {
        responses_file <- paste0(batch_status$metadata$outputInfo$gcsOutputDirectory, "/responses.jsonl")
      } else if (!is.null(batch_status$response$inlinedResponses)) {
        # 인라인 배치 결과 처리 (새로운 구조)
        log_message("INFO", "인라인 배치 응답 발견, 직접 파싱 진행")
        responses <- batch_status$response$inlinedResponses$inlinedResponses
        log_message("INFO", sprintf("인라인 응답 %d개 발견", length(responses)))
        return(responses)
      } else {
        # 레거시 인라인 배치의 경우 직접 응답이 있을 수 있음
        if (!is.null(batch_status$response$candidates)) {
          log_message("INFO", "레거시 인라인 배치 응답 발견, 직접 파싱 진행")
          return(list(batch_status$response))
        }
      }
      
      if (is.null(responses_file) || responses_file == "") {
        stop("배치 결과 파일 경로를 찾을 수 없습니다. 배치 상태를 확인하세요.")
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
      
      # 각 라인을 JSON으로 파싱
      results <- vector("list", length(result_lines))
      for (i in seq_along(result_lines)) {
        results[[i]] <- jsonlite::fromJSON(result_lines[i])
      }
      
      return(results)
    },
    
    # 6. 결과를 데이터프레임으로 변환
    parse_batch_results = function(results, original_data) {
      log_message("INFO", "배치 결과 파싱 중...")
      
      parsed_results <- vector("list", length(results))
      
      for (i in seq_along(results)) {
        result_item <- results[[i]]
        
        # 요청 키로 원본 데이터 매칭 (새로운 구조 지원)
        request_key <- result_item$metadata$key %||% result_item$key
        row_index <- as.numeric(gsub("request-", "", request_key))
        
        if (is.null(result_item$response)) {
          # 오류 케이스
          parsed_results[[i]] <- list(
            row_index = row_index,
            dominant_emotion = "API 오류",
            rationale = result_item$error$message %||% "알 수 없는 오류",
            기쁨 = NA, 신뢰 = NA, 공포 = NA, 놀람 = NA,
            슬픔 = NA, 혐오 = NA, 분노 = NA, 기대 = NA,
            P = NA, A = NA, D = NA,
            complex_emotion = NA,
            emotion_scores_rationale = NA,
            PAD_analysis = NA,
            complex_emotion_reasoning = NA,
            error_message = result_item$error$message %||% "알 수 없는 오류"
          )
        } else {
          # 성공 케이스 - JSON 응답 파싱
          response_text <- result_item$response$candidates[[1]]$content$parts[[1]]$text
          
          tryCatch({
            emotion_result <- parse_emotion_json(response_text)
            emotion_result$row_index <- row_index
            parsed_results[[i]] <- emotion_result
          }, error = function(e) {
            parsed_results[[i]] <- list(
              row_index = row_index,
              dominant_emotion = "파싱 오류",
              rationale = sprintf("JSON 파싱 실패: %s", e$message),
              기쁨 = NA, 신뢰 = NA, 공포 = NA, 놀람 = NA,
              슬픔 = NA, 혐오 = NA, 분노 = NA, 기대 = NA,
              P = NA, A = NA, D = NA,
              complex_emotion = NA,
              emotion_scores_rationale = NA,
              PAD_analysis = NA,
              complex_emotion_reasoning = NA,
              error_message = sprintf("파싱 오류: %s", e$message)
            )
          })
        }
      }
      
      # 데이터프레임으로 변환 (row_index 포함)
      results_df <- do.call(rbind, lapply(parsed_results, function(x) {
        if (is.null(x$row_index)) x$row_index <- NA
        data.frame(x, stringsAsFactors = FALSE)
      }))
      
      # 원본 데이터와 병합
      final_df <- original_data %>%
        mutate(row_index = row_number()) %>%
        left_join(results_df, by = "row_index") %>%
        select(-row_index)
      
      log_message("INFO", sprintf("결과 파싱 완료: %d행", nrow(final_df)))
      return(final_df)
    }
  )
)

# JSON 파싱 함수 (기존 함수와 동일)
parse_emotion_json <- function(json_text) {
  # 기존 parse_emotion_json 함수 로직 사용
  # (functions.R에서 가져오기)
  if (file.exists(PATHS$functions_file)) {
    source(PATHS$functions_file, encoding = "UTF-8")
    return(parse_emotion_json_internal(json_text))
  } else {
    stop("functions.R 파일을 찾을 수 없습니다.")
  }
}

# 메인 배치 처리 실행 함수
run_batch_emotion_analysis <- function(sample_mode = "ask", submit_only = FALSE) {
  log_message("INFO", "=== 배치 처리 감정분석 시작 ===")
  
  # 1. 데이터 로드
  if (!file.exists(PATHS$prompts_data)) {
    stop("⚠️ prompts_ready.RDS 파일을 찾을 수 없습니다.")
  }
  
  full_corpus_with_prompts <- readRDS(PATHS$prompts_data)
  log_message("INFO", "프롬프트 데이터 로드 완료")
  
  # 2. 분석 모드 결정 (배치 처리용 간소화 메뉴)
  if (sample_mode == "ask") {
    selected_mode <- get_batch_analysis_mode()
    
    # 사용자가 취소를 선택한 경우
    if (is.null(selected_mode)) {
      log_message("INFO", "사용자가 배치 처리를 취소했습니다.")
      return(NULL)
    }
  } else {
    selected_mode <- sample_mode
  }
  
  # 3. 샘플링 (기존 로직 사용)
  if (selected_mode %in% c("code_check", "pilot", "sampling", "full")) {
    raw_sample <- get_sample_for_mode(full_corpus_with_prompts, selected_mode)
  } else {
    stop("배치 처리는 4단계 모드만 지원합니다.")
  }
  
  # 4. 기분석 데이터 필터링
  data_to_process <- tracker$filter_unanalyzed(
    raw_sample,
    exclude_types = c("batch", "sample", "test", "full", "adaptive_sample"),
    model_filter = BATCH_CONFIG$model_name,
    days_back = 30
  )
  
  # 분석 제외 대상 필터링
  data_skipped <- data_to_process %>%
    mutate(content_cleaned = trimws(content)) %>%
    filter(
      is.na(content_cleaned) | content_cleaned == "" |
        content_cleaned %in% c("내용 없음", "삭제된 댓글입니다.", "비밀 댓글입니다.") |
        str_detect(content_cleaned, "작성자가 (댓글|글)을 삭제하였습니다") |
        str_length(content_cleaned) <= 2 |
        !str_detect(content_cleaned, "[가-힣A-Za-z]")
    ) %>%
    select(-content_cleaned)
  
  data_for_batch <- data_to_process %>%
    anti_join(data_skipped, by = c("post_id", "comment_id"))
  
  log_message("INFO", sprintf("배치 처리 대상: %d건", nrow(data_for_batch)))
  
  if (nrow(data_for_batch) == 0) {
    log_message("INFO", "새로 분석할 데이터가 없습니다.")
    return(NULL)
  }
  
  # 5. 배치 처리 실행
  processor <- BatchProcessor$new()
  
  # 임시 파일 경로
  batch_file <- file.path(tempdir(), sprintf("batch_input_%s.jsonl", 
                                           format(Sys.time(), "%Y%m%d_%H%M%S")))
  
  tryCatch({
    # 배치 파일 생성
    processor$create_batch_file(data_for_batch, batch_file)
    
    # 파일 업로드
    file_uri <- processor$upload_file(batch_file)
    
    # 배치 작업 생성
    batch_name <- processor$create_batch_job(file_uri, batch_file)
    
    log_message("INFO", sprintf("배치 작업 생성됨: %s", batch_name))
    log_message("INFO", sprintf("⏳ 배치 처리가 시작되었습니다. %d시간 내 완료 예정...", 
                               BATCH_CONFIG$expected_processing_hours))
    log_message("INFO", sprintf("💰 배치 처리 비용: 표준 요금의 %d%%", 
                               BATCH_CONFIG$cost_savings_percentage))
    
    # 배치 작업명을 파일로 저장 (모니터링 편의성)
    batch_info_file <- file.path(PATHS$results_dir, "current_batch_jobs.txt")
    batch_info <- sprintf("[%s] %s - %s 모드 (%d건)\n", 
                         format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                         batch_name, selected_mode, nrow(data_for_batch))
    
    if (file.exists(batch_info_file)) {
      cat(batch_info, file = batch_info_file, append = TRUE)
    } else {
      cat("=== 배치 작업 이력 ===\n", file = batch_info_file)
      cat(batch_info, file = batch_info_file, append = TRUE)
    }
    
    cat("📋 배치 작업명이 다음 파일에 저장되었습니다:\n")
    cat(sprintf("   %s\n", batch_info_file))
    cat("💡 배치 모니터링 시 이 이름을 사용하세요:\n")
    cat(sprintf("   %s\n", batch_name))
    
    # 상태 모니터링
    batch_status <- processor$monitor_batch_job(batch_name)
    
    # 결과 다운로드 및 파싱
    results <- processor$download_results(batch_status)
    final_df <- processor$parse_batch_results(results, data_for_batch)
    
    # 건너뛴 데이터 추가
    if (nrow(data_skipped) > 0) {
      skipped_final_df <- data_skipped %>%
        mutate(
          기쁨 = NA_real_, 신뢰 = NA_real_, 공포 = NA_real_, 놀람 = NA_real_,
          슬픔 = NA_real_, 혐오 = NA_real_, 분노 = NA_real_, 기대 = NA_real_,
          P = NA_real_, A = NA_real_, D = NA_real_,
          complex_emotion = NA_character_,
          emotion_scores_rationale = "분석 제외 (배치 처리 필터링)",
          PAD_analysis = NA_character_,
          complex_emotion_reasoning = NA_character_,
          dominant_emotion = "분석 제외",
          rationale = "필터링된 내용 (삭제, 단문 등)",
          unexpected_emotions = NA_character_,
          error_message = NA_character_
        )
      
      final_df <- bind_rows(final_df, skipped_final_df) %>%
        arrange(post_id, if("comment_id" %in% names(.)) comment_id else NULL)
    }
    
    # 6. 결과 저장 (03 스크립트와 동일한 파일명 체계, 타임스탬프 포함)
    rds_filename <- generate_filepath(selected_mode, nrow(data_for_batch), ".RDS", is_batch = TRUE)
    csv_filename <- generate_filepath(selected_mode, nrow(data_for_batch), ".csv", is_batch = TRUE)
    
    saveRDS(final_df, rds_filename)
    readr::write_excel_csv(final_df, csv_filename, na = "")
    
    # 분석 이력 등록 (03 스크립트와 통합)
    tracker$register_analysis(
      final_df %>% filter(dominant_emotion != "분석 제외"),
      analysis_type = paste0("batch_", selected_mode),
      model_used = BATCH_CONFIG$model_name,
      analysis_file = "04_배치처리_감정분석"
    )
    
    # 결과 메시지
    log_message("INFO", sprintf("분석 결과가 '%s' 및 '%s' 파일로 저장되었습니다.", 
                               basename(rds_filename), basename(csv_filename)))
    
    log_message("INFO", sprintf("배치 처리 완료! 결과 저장: %s", basename(rds_filename)))
    log_message("INFO", "=== 배치 처리 감정분석 완료 ===")
    
    return(final_df)
    
  }, finally = {
    # 임시 파일 정리 (config 설정에 따라)
    if (BATCH_CONFIG$cleanup_temp_files && file.exists(batch_file)) {
      file.remove(batch_file)
      if (BATCH_CONFIG$detailed_logging) {
        log_message("INFO", "임시 배치 파일 정리 완료")
      }
    } else if (BATCH_CONFIG$backup_batch_requests && file.exists(batch_file)) {
      # 배치 요청 백업
      backup_dir <- file.path(dirname(batch_file), "batch_backups")
      if (!dir.exists(backup_dir)) {
        dir.create(backup_dir, recursive = TRUE)
      }
      backup_file <- file.path(backup_dir, sprintf("backup_%s_%s.jsonl", 
                                                  format(Sys.time(), "%Y%m%d_%H%M%S"),
                                                  basename(batch_file)))
      file.copy(batch_file, backup_file)
      if (BATCH_CONFIG$detailed_logging) {
        log_message("INFO", sprintf("배치 요청 백업 저장: %s", basename(backup_file)))
      }
    }
  })
}

# 실행부 - 메인 함수 정의 (바로 선택 메뉴 시작)
run_main <- function() {
  # 바로 모드 선택 및 배치 처리 시작
  result <- run_batch_emotion_analysis()
  
  if (!is.null(result)) {
    cat("\n", rep("=", 70), "\n")
    cat("🎉 배치 처리가 성공적으로 완료되었습니다!\n")
    cat(sprintf("📊 처리된 데이터: %d건\n", nrow(result)))
    cat(sprintf("💰 비용 절약: %d%% 할인 적용\n", BATCH_CONFIG$cost_savings_percentage))
    cat("💾 결과가 results 폴더에 저장되었습니다.\n")
    cat(rep("=", 70), "\n")
  } else {
    cat("\n❌ 배치 처리가 실패했거나 취소되었습니다.\n")
  }
  
  return(result)
}

# 초기화 완료 메시지
cat("\n", rep("=", 70), "\n")
cat("🎉 04_배치처리_감정분석.R 스크립트 초기화 완료!\n")
cat(rep("=", 70), "\n")

# 스크립트 실행 시 자동으로 선택 대화창 시작
if (!interactive()) {
  # 명령줄 모드: 바로 메뉴 실행
  cat("📟 명령줄 모드에서 배치 처리를 시작합니다...\n\n")
  run_main()
} else {
  # 대화형 모드: 바로 선택 메뉴 시작
  cat("🚀 배치 처리 모드를 선택하세요...\n\n")
  
  # 자동으로 선택 메뉴 실행
  tryCatch({
    run_main()
  }, error = function(e) {
    cat("\n❌ 배치 처리 중 오류가 발생했습니다:\n")
    cat("오류 메시지:", e$message, "\n\n")
    cat("💡 문제 해결 방법:\n")
    cat("1. API 키 설정 확인: Sys.getenv('GEMINI_API_KEY')\n")
    cat("2. 필요한 파일들 존재 확인\n")
    cat("3. 인터넷 연결 상태 확인\n")
    cat("4. 다시 시도: run_main()\n")
  })
}

# 배치 처리 전용 분석 모드 선택 함수 (간소화된 메뉴)
get_batch_analysis_mode <- function() {
  
  cat("🔄 배치 처리 모드 선택 (50% 할인, 24시간 내 처리)\n")
  cat(rep("-", 50), "\n")
  
  cat("1. 코드 점검      - 1개 게시물 (프롬프트 검증)\n")
  cat("2. 파일럿 분석    - 5개 게시물 (방법론 검증)\n") 
  cat("3. 샘플링 분석    - 384+ 샘플 (통계적 유의성)\n")
  cat("4. 전체 분석      - 모든 데이터 (완전 분석)\n")
  cat(rep("-", 50), "\n")
  
  while(TRUE) {
    choice <- readline("선택 (1-4): ")
    
    if (choice == "1") {
      cat("\n🔧 코드 점검 모드로 배치 처리를 시작합니다...\n")
      return("code_check")
    } else if (choice == "2") {
      cat("\n🧪 파일럿 분석 모드로 배치 처리를 시작합니다...\n")
      return("pilot")
    } else if (choice == "3") {
      cat("\n📊 샘플링 분석 모드로 배치 처리를 시작합니다...\n")
      return("sampling")
    } else if (choice == "4") {
      cat("\n🌍 전체 분석 모드로 배치 처리를 시작합니다...\n")
      return("full")
    } else if (choice == "0" || tolower(choice) == "q") {
      cat("\n👋 배치 처리를 취소합니다.\n")
      return(NULL)
    } else {
      cat("❌ 잘못된 선택입니다. 1-4를 입력하세요 (0:취소)\n")
    }
  }
}