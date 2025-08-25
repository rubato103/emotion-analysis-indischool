# Gemini API 배치 요청 스크립트
# 목적: 대량 데이터를 할인된 비용으로 배치 처리 요청만 담당
# 특징: 요청 생성 및 제출 전담, 모니터링은 06 스크립트에서 담당

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

# 배치 요청 전담 클래스
BatchRequestor <- R6Class("BatchRequestor",
  public = list(
    api_key = NULL,
    base_url = "https://generativelanguage.googleapis.com/v1beta",
    
    initialize = function() {
      self$api_key <- Sys.getenv("GEMINI_API_KEY")
      if (self$api_key == "") {
        stop("⚠️ Gemini API 키가 설정되지 않았습니다.")
      }
      log_message("INFO", "배치 요청기 초기화 완료")
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
        # 기존 완성된 프롬프트 사용 + 배치용 JSON 지시만 추가
        if ("prompt" %in% names(data) && !is.na(data$prompt[i])) {
          # 01번 스크립트에서 생성된 완성 프롬프트 사용
          base_prompt <- data$prompt[i]
          batch_prompt <- paste0(base_prompt, PROMPT_CONFIG$batch_json_instruction)
        } else {
          # 폴백: 프롬프트가 없으면 새로 생성
          batch_prompt <- create_analysis_prompt(
            text = data$content[i],
            구분 = data$구분[i],
            title = if("title" %in% names(data)) data$title[i] else NULL,
            context = if("context" %in% names(data)) data$context[i] else NULL,
            context_title = if("context_title" %in% names(data)) data$context_title[i] else NULL,
            batch_mode = TRUE  # 배치 모드 활성화
          )
        }
        
        # Google 공식 JSONL 형식: key + request 구조
        # {"key": "request-1", "request": {...}}
        jsonl_obj <- list(
          key = sprintf("request-%d", i),
          request = list(
            contents = list(
              list(
                parts = list(
                  list(text = batch_prompt)
                )
              )
            )
          )
        )
        
        # JSONL 라인 형식: key + request 구조
        jsonl_lines[i] <- jsonlite::toJSON(jsonl_obj, auto_unbox = TRUE)
      }
      
      # JSONL 파일 작성
      writeLines(jsonl_lines, file_path, useBytes = TRUE)
      
      # 디버깅: 생성된 JSONL 파일의 첫 몇 라인 확인
      if (length(jsonl_lines) > 0) {
        log_message("DEBUG", sprintf("JSONL 첫 번째 라인: %s", substr(jsonl_lines[1], 1, 200)))
        if (length(jsonl_lines) > 1) {
          log_message("DEBUG", sprintf("JSONL 두 번째 라인: %s", substr(jsonl_lines[2], 1, 200)))
        }
      }
      
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
      full_uri <- upload_result$file$uri
      
      # 파일 ID만 추출 (files/xxxxx 형식)
      file_id <- sub(".*/(files/[^/]+).*", "\\1", full_uri)
      if (!grepl("^files/", file_id)) {
        # 경로에서 files/ 부분이 없으면 파일명만 추출하여 추가
        file_name <- basename(full_uri)
        file_id <- paste0("files/", file_name)
      }
      
      log_message("INFO", sprintf("파일 업로드 완료: %s (ID: %s)", full_uri, file_id))
      return(file_id)
    },
    
    # 3. 배치 작업 생성 및 제출
    submit_batch_job = function(file_id, batch_file, selected_mode, data_count) {
      log_message("INFO", "배치 작업 생성 중...")
      
      # 파일 요청 방식으로 배치 요청 생성 (단순화된 형식)
      batch_request <- list(
        batch = list(
          display_name = sprintf("emotion_batch_%s", format(Sys.time(), "%Y%m%d_%H%M%S")),
          input_config = list(
            file_name = file_id  # 직접 파일 ID 사용
          )
        )
      )
      
      log_message("INFO", sprintf("파일 요청 방식 사용 - File ID: %s", file_id))
      
      # 디버깅: 전송할 JSON 로깅
      batch_json <- jsonlite::toJSON(batch_request, auto_unbox = TRUE, pretty = TRUE)
      log_message("DEBUG", sprintf("배치 요청 JSON:\n%s", batch_json))
      
      tryCatch({
        # 배치 엔드포인트
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
        
        # 배치 작업명을 파일로 저장
        batch_info_file <- file.path(PATHS$results_dir, "current_batch_jobs.txt")
        batch_info <- sprintf("[%s] %s - %s 모드 (%d건)\n", 
                             format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                             operation_name, selected_mode, data_count)
        
        if (file.exists(batch_info_file)) {
          cat(batch_info, file = batch_info_file, append = TRUE)
        } else {
          cat("=== 배치 작업 이력 ===\n", file = batch_info_file)
          cat(batch_info, file = batch_info_file, append = TRUE)
        }
        
        cat("\n", rep("=", 70), "\n")
        cat("🎉 배치 요청이 성공적으로 제출되었습니다!\n")
        cat(sprintf("📋 배치 작업명: %s\n", operation_name))
        cat(sprintf("📊 처리 대상: %d건\n", data_count))
        cat(sprintf("⏳ 예상 처리 시간: %d시간 내\n", BATCH_CONFIG$expected_processing_hours))
        cat(sprintf("💰 비용 절약: %d%% 할인 적용\n", BATCH_CONFIG$cost_savings_percentage))
        cat("📁 작업 이력이 results/current_batch_jobs.txt에 저장되었습니다.\n")
        cat("\n💡 배치 모니터링 방법:\n")
        cat("   06_batch_monitor.R 스크립트를 실행하세요.\n")
        cat(rep("=", 70), "\n")
        
        return(operation_name)
        
      }, error = function(e) {
        log_message("ERROR", sprintf("배치 작업 생성 실패: %s", e$message))
        
        # 에러 상세 정보 추출
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
    }
  )
)

# 메인 배치 요청 실행 함수
run_batch_request <- function(sample_mode = "ask") {
  log_message("INFO", "=== 배치 요청 시작 ===")
  
  # 1. 데이터 로드
  if (!file.exists(PATHS$prompts_data)) {
    stop("⚠️ prompts_ready.RDS 파일을 찾을 수 없습니다.")
  }
  
  full_corpus_with_prompts <- readRDS(PATHS$prompts_data)
  log_message("INFO", "프롬프트 데이터 로드 완료")
  
  # 2. 분석 모드 결정
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
  data_for_batch <- data_to_process %>%
    mutate(content_cleaned = trimws(content)) %>%
    filter(
      !(is.na(content_cleaned) | content_cleaned == "" |
        content_cleaned %in% c("내용 없음", "삭제된 댓글입니다.", "비밀 댓글입니다.") |
        str_detect(content_cleaned, "작성자가 (댓글|글)을 삭제하였습니다") |
        str_length(content_cleaned) <= 2 |
        !str_detect(content_cleaned, "[가-힣A-Za-z]"))
    ) %>%
    select(-content_cleaned)
  
  log_message("INFO", sprintf("배치 처리 대상: %d건", nrow(data_for_batch)))
  
  if (nrow(data_for_batch) == 0) {
    log_message("INFO", "새로 분석할 데이터가 없습니다.")
    return(NULL)
  }
  
  # 5. 배치 요청 실행
  requestor <- BatchRequestor$new()
  
  # 임시 파일 경로
  batch_file <- file.path(tempdir(), sprintf("batch_input_%s.jsonl", 
                                           format(Sys.time(), "%Y%m%d_%H%M%S")))
  
  tryCatch({
    # 배치 파일 생성
    requestor$create_batch_file(data_for_batch, batch_file)
    
    # 파일 업로드
    file_id <- requestor$upload_file(batch_file)
    
    # 배치 작업 생성 및 제출
    batch_name <- requestor$submit_batch_job(file_id, batch_file, selected_mode, nrow(data_for_batch))
    
    return(list(
      batch_name = batch_name,
      mode = selected_mode,
      count = nrow(data_for_batch)
    ))
    
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

# 실행부 - 메인 함수 정의
run_main <- function() {
  result <- run_batch_request()
  
  if (!is.null(result)) {
    log_message("INFO", "=== 배치 요청 완료 ===")
  } else {
    cat("\n❌ 배치 요청이 실패했거나 취소되었습니다.\n")
  }
  
  return(result)
}

# 배치 처리 전용 분석 모드 선택 함수 (간소화된 메뉴)
get_batch_analysis_mode <- function() {
  
  cat("🔄 배치 요청 모드 선택 (50% 할인, 24시간 내 처리)\n")
  cat(rep("-", 50), "\n")
  
  cat("1. 코드 점검      - 1개 게시물 (프롬프트 검증)\n")
  cat("2. 파일럿 분석    - 5개 게시물 (방법론 검증)\n") 
  cat("3. 샘플링 분석    - 384+ 샘플 (통계적 유의성)\n")
  cat("4. 전체 분석      - 모든 데이터 (완전 분석)\n")
  cat(rep("-", 50), "\n")
  
  while(TRUE) {
    choice <- readline("선택 (1-4): ")
    
    if (choice == "1") {
      cat("\n🔧 코드 점검 모드로 배치 요청을 제출합니다...\n")
      return("code_check")
    } else if (choice == "2") {
      cat("\n🧪 파일럿 분석 모드로 배치 요청을 제출합니다...\n")
      return("pilot")
    } else if (choice == "3") {
      cat("\n📊 샘플링 분석 모드로 배치 요청을 제출합니다...\n")
      return("sampling")
    } else if (choice == "4") {
      cat("\n🌍 전체 분석 모드로 배치 요청을 제출합니다...\n")
      return("full")
    } else if (choice == "0" || tolower(choice) == "q") {
      cat("\n👋 배치 요청을 취소합니다.\n")
      return(NULL)
    } else {
      cat("❌ 잘못된 선택입니다. 1-4를 입력하세요 (0:취소)\n")
    }
  }
}

# 초기화 완료 메시지
cat("\n", rep("=", 70), "\n")
cat("🎉 05_배치요청.R 스크립트 초기화 완료!\n")
cat("📝 역할: 배치 처리 요청 전담 (모니터링/다운로드는 06 스크립트)\n")
cat(rep("=", 70), "\n")

# 스크립트 실행 시 자동으로 선택 대화창 시작
if (!interactive()) {
  # 명령줄 모드: 바로 메뉴 실행
  cat("📟 명령줄 모드에서 배치 요청을 시작합니다...\n\n")
  run_main()
} else {
  # 대화형 모드: 바로 선택 메뉴 시작
  cat("🚀 배치 요청 모드를 선택하세요...\n\n")
  
  # 자동으로 선택 메뉴 실행
  tryCatch({
    run_main()
  }, error = function(e) {
    cat("\n❌ 배치 요청 중 오류가 발생했습니다:\n")
    cat("오류 메시지:", e$message, "\n\n")
    cat("💡 문제 해결 방법:\n")
    cat("1. API 키 설정 확인: Sys.getenv('GEMINI_API_KEY')\n")
    cat("2. 필요한 파일들 존재 확인\n")
    cat("3. 인터넷 연결 상태 확인\n")
    cat("4. 다시 시도: run_main()\n")
  })
}