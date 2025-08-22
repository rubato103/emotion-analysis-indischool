# 배치 작업 모니터링 및 관리 도구
# 목적: 진행 중인 배치 작업 상태 확인, 취소, 결과 다운로드

source("config.R")
source("utils.R")

# 필요한 패키지 로드
required_packages <- c("dplyr", "httr2", "jsonlite")
lapply(required_packages, library, character.only = TRUE)

# 배치 모니터 클래스
BatchMonitor <- R6Class("BatchMonitor",
  public = list(
    api_key = NULL,
    base_url = BATCH_CONFIG$base_url,
    
    initialize = function() {
      self$api_key <- Sys.getenv("GEMINI_API_KEY")
      if (self$api_key == "") {
        stop("⚠️ Gemini API 키가 설정되지 않았습니다.")
      }
    },
    
    # 배치 작업 목록 조회
    list_batch_jobs = function() {
      cat("=== 배치 작업 목록 ===\n")
      
      tryCatch({
        response <- httr2::request(sprintf("%s/batches", self$base_url)) %>%
          httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
          httr2::req_perform()
        
        batch_list <- httr2::resp_body_json(response)
        
        if (length(batch_list$batches) == 0) {
          cat("📭 진행 중인 배치 작업이 없습니다.\n")
          return(invisible(NULL))
        }
        
        for (i in seq_along(batch_list$batches)) {
          batch <- batch_list$batches[[i]]
          cat(sprintf("\n🔄 배치 #%d\n", i))
          cat(sprintf("   이름: %s\n", batch$name))
          cat(sprintf("   표시명: %s\n", batch$display_name %||% "없음"))
          cat(sprintf("   상태: %s\n", batch$state))
          cat(sprintf("   생성일: %s\n", batch$create_time))
          if (!is.null(batch$update_time)) {
            cat(sprintf("   수정일: %s\n", batch$update_time))
          }
        }
        
      }, error = function(e) {
        cat(sprintf("❌ 배치 목록 조회 실패: %s\n", e$message))
      })
    },
    
    # 특정 배치 작업 상태 조회
    get_batch_status = function(batch_name) {
      tryCatch({
        response <- httr2::request(sprintf("%s/%s", self$base_url, batch_name)) %>%
          httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
          httr2::req_perform()
        
        batch_status <- httr2::resp_body_json(response)
        
        cat(sprintf("=== 배치 작업 상태: %s ===\n", batch_name))
        cat(sprintf("상태: %s\n", batch_status$metadata$state))
        cat(sprintf("생성일: %s\n", batch_status$metadata$create_time))
        
        if (!is.null(batch_status$metadata$update_time)) {
          cat(sprintf("수정일: %s\n", batch_status$metadata$update_time))
        }
        
        # 통계 정보
        if (!is.null(batch_status$metadata$batch_stats)) {
          stats <- batch_status$metadata$batch_stats
          cat("\n📊 처리 통계:\n")
          cat(sprintf("  총 요청: %s\n", stats$total_request_count %||% "알 수 없음"))
          cat(sprintf("  성공: %s\n", stats$successful_request_count %||% "알 수 없음"))
          cat(sprintf("  실패: %s\n", stats$failed_request_count %||% "알 수 없음"))
        }
        
        # 오류 정보
        if (!is.null(batch_status$error)) {
          cat(sprintf("\n❌ 오류: %s\n", batch_status$error$message))
        }
        
        return(batch_status)
        
      }, error = function(e) {
        cat(sprintf("❌ 배치 상태 조회 실패: %s\n", e$message))
        return(NULL)
      })
    },
    
    # 배치 작업 취소
    cancel_batch_job = function(batch_name) {
      cat(sprintf("⚠️  배치 작업을 취소합니다: %s\n", batch_name))
      
      tryCatch({
        response <- httr2::request(sprintf("%s/%s:cancel", self$base_url, batch_name)) %>%
          httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
          httr2::req_method("POST") %>%
          httr2::req_perform()
        
        cat("✅ 배치 작업이 취소되었습니다.\n")
        
        # 취소 후 상태 확인
        Sys.sleep(BATCH_CONFIG$status_check_delay_seconds)
        self$get_batch_status(batch_name)
        
      }, error = function(e) {
        cat(sprintf("❌ 배치 취소 실패: %s\n", e$message))
      })
    },
    
    # 완료된 배치 결과 다운로드
    download_batch_results = function(batch_name, output_file = NULL) {
      batch_status <- self$get_batch_status(batch_name)
      
      if (is.null(batch_status)) {
        return(invisible(NULL))
      }
      
      if (batch_status$metadata$state != "BATCH_STATE_SUCCEEDED") {
        cat("⚠️  배치 작업이 아직 완료되지 않았습니다.\n")
        cat(sprintf("현재 상태: %s\n", batch_status$metadata$state))
        return(invisible(NULL))
      }
      
      if (is.null(output_file)) {
        output_file <- sprintf("batch_results_%s_%s.jsonl", 
                              gsub("batches/", "", batch_name),
                              format(Sys.time(), BATCH_CONFIG$file_name_format))
      }
      
      tryCatch({
        # 배치 상태 구조 디버깅
        cat("🔍 배치 상태 구조 확인:\n")
        cat(jsonlite::toJSON(batch_status, auto_unbox = TRUE, pretty = TRUE), "\n")
        
        # 다양한 경로에서 결과 파일 찾기
        responses_file <- NULL
        
        if (!is.null(batch_status$response$responsesFile)) {
          responses_file <- batch_status$response$responsesFile
        } else if (!is.null(batch_status$response$responses_file)) {
          responses_file <- batch_status$response$responses_file
        } else if (!is.null(batch_status$metadata$outputInfo$outputFile)) {
          responses_file <- batch_status$metadata$outputInfo$outputFile
        } else if (!is.null(batch_status$response$inlinedResponses)) {
          # 인라인 배치 결과 처리 (inlinedResponses 구조)
          cat("인라인 배치 결과 발견, JSONL 형식으로 저장합니다.\n")
          
          responses <- batch_status$response$inlinedResponses$inlinedResponses
          jsonl_lines <- vector("character", length(responses))
          
          for (i in seq_along(responses)) {
            # 각 응답을 JSONL 라인으로 변환
            response_item <- responses[[i]]
            jsonl_lines[i] <- jsonlite::toJSON(response_item, auto_unbox = TRUE)
          }
          
          # JSONL 파일로 저장
          writeLines(jsonl_lines, output_file)
          cat(sprintf("✅ 인라인 배치 결과 저장 완료: %s (%d개 응답)\n", output_file, length(responses)))
          
          # 자동으로 파싱 및 최종 결과 생성 (03 스크립트 통합 체계)
          cat("🔄 배치 결과를 최종 형식으로 변환 중...\n")
          tryCatch({
            # 절대 경로로 로드
            process_file <- "C:/Users/rubat/SynologyDrive/R project/emotion_analysis/process_batch_results.R"
            source(process_file, local = TRUE)
            # 배치 표시명에서 모드 추출 시도
            analysis_mode <- "manual"
            if (!is.null(batch_status$metadata$displayName)) {
              display_name <- batch_status$metadata$displayName
              if (grepl("code_check", display_name, ignore.case = TRUE)) analysis_mode <- "code_check"
              else if (grepl("pilot", display_name, ignore.case = TRUE)) analysis_mode <- "pilot" 
              else if (grepl("sampling", display_name, ignore.case = TRUE)) analysis_mode <- "sampling"
              else if (grepl("full", display_name, ignore.case = TRUE)) analysis_mode <- "full"
            }
            
            final_result <- process_completed_batch(output_file, analysis_mode = analysis_mode)
            cat("✅ 최종 결과 생성 완료! results 디렉토리의 CSV와 RDS 파일을 확인하세요.\n")
            cat("📊 03 스크립트와 동일한 형식으로 저장되어 통합 관리됩니다.\n")
          }, error = function(e) {
            cat(sprintf("⚠️ 결과 파싱 중 오류 발생: %s\n", e$message))
            cat("💡 수동으로 process_completed_batch()를 실행하세요.\n")
          })
          
          return(output_file)
        } else if (!is.null(batch_status$response$candidates)) {
          # 단일 응답 케이스
          cat("단일 배치 응답 발견, 직접 저장합니다.\n")
          result_content <- jsonlite::toJSON(batch_status$response, auto_unbox = TRUE)
          writeLines(result_content, output_file)
          cat(sprintf("✅ 단일 배치 결과 저장 완료: %s\n", output_file))
          return(output_file)
        }
        
        if (is.null(responses_file) || responses_file == "") {
          stop(sprintf("결과 파일 경로를 찾을 수 없습니다. 배치 상태: %s", 
                      jsonlite::toJSON(batch_status, auto_unbox = TRUE)))
        }
        
        cat(sprintf("결과 파일: %s\n", responses_file))
        
        download_url <- sprintf("%s/download/v1beta/%s:download?alt=media", 
                               gsub("/v1beta", "", BATCH_CONFIG$base_url), responses_file)
        
        response <- httr2::request(download_url) %>%
          httr2::req_headers(`x-goog-api-key` = self$api_key) %>%
          httr2::req_perform()
        
        # 결과를 파일로 저장
        result_content <- httr2::resp_body_string(response)
        writeLines(result_content, output_file)
        
        cat(sprintf("✅ 배치 결과 다운로드 완료: %s\n", output_file))
        return(output_file)
        
      }, error = function(e) {
        cat(sprintf("❌ 결과 다운로드 실패: %s\n", e$message))
        return(NULL)
      })
    }
  )
)

# 대화형 배치 관리 함수
interactive_batch_manager <- function() {
  monitor <- BatchMonitor$new()
  
  repeat {
    cat("\n=== 배치 작업 관리자 ===\n")
    cat("1. 배치 작업 목록 보기\n")
    cat("2. 특정 배치 상태 확인\n")
    cat("3. 배치 작업 취소\n")
    cat("4. 완료된 결과 다운로드\n")
    cat("5. 최근 배치 작업 이력 보기\n")
    cat("6. 종료\n")
    
    # 최근 배치 작업 이력 파일 확인
    batch_info_file <- file.path(PATHS$results_dir, "current_batch_jobs.txt")
    if (file.exists(batch_info_file)) {
      cat("💡 최근 배치 작업 이력이 있습니다. 메뉴 5번을 확인하세요.\n")
    }
    
    choice <- readline("선택하세요 (1-6): ")
    
    if (choice == "1") {
      monitor$list_batch_jobs()
      
    } else if (choice == "2") {
      batch_name <- readline("배치 이름을 입력하세요 (예: batches/123456): ")
      monitor$get_batch_status(batch_name)
      
    } else if (choice == "3") {
      batch_name <- readline("취소할 배치 이름을 입력하세요: ")
      confirm <- readline("정말 취소하시겠습니까? (y/N): ")
      if (tolower(confirm) == "y") {
        monitor$cancel_batch_job(batch_name)
      }
      
    } else if (choice == "4") {
      batch_name <- readline("다운로드할 배치 이름을 입력하세요: ")
      output_file <- readline("출력 파일명 (엔터=자동 생성): ")
      if (output_file == "") output_file <- NULL
      monitor$download_batch_results(batch_name, output_file)
      
    } else if (choice == "5") {
      # 최근 배치 작업 이력 표시
      batch_info_file <- file.path(PATHS$results_dir, "current_batch_jobs.txt")
      if (file.exists(batch_info_file)) {
        cat("\n=== 최근 배치 작업 이력 ===\n")
        batch_content <- readLines(batch_info_file)
        for (line in batch_content) {
          cat(line, "\n")
        }
        cat("\n💡 배치 이름을 복사하여 다른 메뉴에서 사용하세요.\n")
      } else {
        cat("📭 배치 작업 이력이 없습니다.\n")
      }
      
    } else if (choice == "6") {
      cat("👋 배치 관리자를 종료합니다.\n")
      break
      
    } else {
      cat("⚠️  올바른 번호를 선택해주세요.\n")
    }
  }
}

# 스크립트 직접 실행 시
if (!interactive()) {
  interactive_batch_manager()
}