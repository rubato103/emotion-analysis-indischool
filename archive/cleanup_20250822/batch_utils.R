# 배치 처리 유틸리티 함수
# 목적: 배치 처리 워크플로우를 간소화하는 통합 함수 제공

# 설정 로드
source("config.R")
source("utils.R")

# 필요 패키지 로드
required_packages <- c("dplyr", "stringr", "jsonlite", "httr2")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)

# ============================================================================
# 통합 배치 처리 함수
# ============================================================================

# 1. 배치 작업 실행 및 모니터링 통합 함수
run_batch_with_monitoring <- function(mode = "code_check", 
                                     auto_download = TRUE,
                                     max_wait_hours = NULL) {
  
  cat("\n", rep("=", 70), "\n")
  cat("🚀 통합 배치 처리 시작\n")
  cat(rep("=", 70), "\n")
  
  # 1단계: 배치 작업 제출
  cat("\n📤 1단계: 배치 작업 제출 중...\n")
  
  # 04_batch_emotion_analysis.R의 함수 사용
  source("04_batch_emotion_analysis.R", local = TRUE)
  
  # 배치 작업 시작
  batch_result <- run_batch_emotion_analysis(mode, submit_only = TRUE)
  
  if (is.null(batch_result) || is.null(batch_result$batch_name)) {
    cat("❌ 배치 작업 제출 실패\n")
    return(NULL)
  }
  
  batch_id <- batch_result$batch_name
  cat(sprintf("✅ 배치 작업 제출 완료: %s\n", batch_id))
  
  # 2단계: 작업 모니터링
  cat("\n⏳ 2단계: 배치 작업 모니터링...\n")
  
  if (is.null(max_wait_hours)) {
    max_wait_hours <- BATCH_CONFIG$max_wait_hours
  }
  
  # 모니터링 시작
  start_time <- Sys.time()
  poll_interval <- BATCH_CONFIG$poll_interval_seconds
  
  while (TRUE) {
    # 상태 확인
    status <- check_batch_status_safe(batch_id)
    
    if (is.null(status)) {
      cat("⚠️ 배치 상태 확인 실패. 재시도 중...\n")
      Sys.sleep(poll_interval)
      next
    }
    
    current_state <- status$state %||% "UNKNOWN"
    elapsed_time <- difftime(Sys.time(), start_time, units = "mins")
    
    # 진행 상황 표시
    cat(sprintf("\r상태: %s | 경과 시간: %.1f분", 
                current_state, as.numeric(elapsed_time)))
    
    # 완료 상태 확인
    if (current_state == "COMPLETED") {
      cat("\n✅ 배치 작업 완료!\n")
      break
    } else if (current_state %in% c("FAILED", "CANCELLED")) {
      cat(sprintf("\n❌ 배치 작업 실패: %s\n", current_state))
      return(NULL)
    }
    
    # 타임아웃 확인
    if (as.numeric(elapsed_time) > max_wait_hours * 60) {
      cat("\n⏱️ 최대 대기 시간 초과\n")
      return(NULL)
    }
    
    Sys.sleep(poll_interval)
  }
  
  # 3단계: 결과 다운로드 (선택적)
  if (auto_download) {
    cat("\n📥 3단계: 결과 다운로드 및 처리...\n")
    
    # 06_batch_monitor.R의 함수 사용
    source("06_batch_monitor.R", local = TRUE)
    
    result <- download_and_parse_batch(batch_id, status)
    
    if (!is.null(result)) {
      # 결과 저장
      save_batch_results(result, batch_id)
      
      cat(sprintf("\n🎉 배치 처리 완전 완료!\n"))
      cat(sprintf("   - 처리된 항목: %d개\n", nrow(result)))
      cat(sprintf("   - 모드: %s\n", mode))
      cat(sprintf("   - 총 소요 시간: %.1f분\n", as.numeric(elapsed_time)))
      
      return(result)
    }
  }
  
  return(list(batch_id = batch_id, status = status))
}

# 2. 안전한 배치 상태 확인 함수
check_batch_status_safe <- function(batch_id, max_retries = 3) {
  
  api_key <- Sys.getenv("GEMINI_API_KEY")
  if (api_key == "") {
    stop("GEMINI_API_KEY가 설정되지 않았습니다.")
  }
  
  base_url <- BATCH_CONFIG$base_url %||% "https://generativelanguage.googleapis.com/v1beta"
  url <- paste0(base_url, "/", batch_id)
  
  for (i in 1:max_retries) {
    tryCatch({
      response <- request(url) %>%
        req_headers("X-Goog-Api-Key" = api_key) %>%
        req_perform()
      
      status_data <- resp_body_json(response)
      return(status_data)
      
    }, error = function(e) {
      if (i < max_retries) {
        Sys.sleep(2)  # 재시도 전 대기
      } else {
        return(NULL)
      }
    })
  }
  
  return(NULL)
}

# 3. 배치 작업 재개 함수
resume_batch_monitoring <- function(batch_id, auto_download = TRUE) {
  
  cat("\n📌 기존 배치 작업 재개\n")
  cat(sprintf("배치 ID: %s\n", batch_id))
  
  # 상태 확인
  status <- check_batch_status_safe(batch_id)
  
  if (is.null(status)) {
    cat("❌ 배치 작업을 찾을 수 없습니다.\n")
    return(NULL)
  }
  
  current_state <- status$state %||% "UNKNOWN"
  
  if (current_state == "COMPLETED") {
    cat("✅ 배치 작업이 이미 완료되었습니다.\n")
    
    if (auto_download) {
      cat("📥 결과 다운로드 중...\n")
      
      source("06_batch_monitor.R", local = TRUE)
      result <- download_and_parse_batch(batch_id, status)
      
      if (!is.null(result)) {
        save_batch_results(result, batch_id)
        return(result)
      }
    }
  } else if (current_state == "ACTIVE") {
    cat("🔄 배치 작업이 진행 중입니다. 모니터링을 계속합니다...\n")
    
    # 모니터링 재개
    return(run_batch_with_monitoring(auto_download = auto_download))
    
  } else {
    cat(sprintf("⚠️ 배치 작업 상태: %s\n", current_state))
  }
  
  return(NULL)
}

# 4. 배치 작업 일괄 처리 함수
process_multiple_batches <- function(modes = c("code_check", "pilot", "sampling"),
                                    sequential = TRUE) {
  
  results_list <- list()
  
  for (mode in modes) {
    cat(sprintf("\n\n🔄 %s 모드 배치 처리 시작...\n", mode))
    
    result <- run_batch_with_monitoring(mode = mode, auto_download = TRUE)
    
    if (!is.null(result)) {
      results_list[[mode]] <- result
      cat(sprintf("✅ %s 모드 완료\n", mode))
    } else {
      cat(sprintf("❌ %s 모드 실패\n", mode))
      
      if (sequential) {
        cat("순차 처리 모드이므로 중단합니다.\n")
        break
      }
    }
  }
  
  return(results_list)
}

# 5. 배치 작업 정리 함수
cleanup_old_batch_jobs <- function(days_old = 7) {
  
  cat("\n🧹 오래된 배치 작업 정리...\n")
  
  # 배치 작업 목록 파일 확인
  batch_list_file <- "results/current_batch_jobs.txt"
  
  if (!file.exists(batch_list_file)) {
    cat("정리할 배치 작업이 없습니다.\n")
    return()
  }
  
  # 파일 읽기 및 날짜 확인
  batch_lines <- readLines(batch_list_file)
  current_time <- Sys.time()
  
  new_lines <- character()
  removed_count <- 0
  
  for (line in batch_lines) {
    # 날짜 추출 (형식: [YYYY-MM-DD HH:MM:SS])
    date_match <- str_extract(line, "\\[([^\\]]+)\\]")
    
    if (!is.na(date_match)) {
      date_str <- gsub("\\[|\\]", "", date_match)
      batch_time <- as.POSIXct(date_str, format = "%Y-%m-%d %H:%M:%S")
      
      days_diff <- as.numeric(difftime(current_time, batch_time, units = "days"))
      
      if (days_diff <= days_old) {
        new_lines <- c(new_lines, line)
      } else {
        removed_count <- removed_count + 1
      }
    } else {
      new_lines <- c(new_lines, line)
    }
  }
  
  # 파일 업데이트
  if (removed_count > 0) {
    writeLines(new_lines, batch_list_file)
    cat(sprintf("✅ %d개의 오래된 배치 작업 기록이 정리되었습니다.\n", removed_count))
  } else {
    cat("정리할 오래된 배치 작업이 없습니다.\n")
  }
}

# 사용 예시 출력
if (!interactive()) {
  cat("\n")
  cat("=== 배치 처리 유틸리티 함수 로드 완료 ===\n")
  cat("\n사용 가능한 함수:\n")
  cat("  • run_batch_with_monitoring() - 배치 작업 실행 및 모니터링\n")
  cat("  • resume_batch_monitoring() - 기존 배치 작업 재개\n")
  cat("  • process_multiple_batches() - 여러 모드 일괄 처리\n")
  cat("  • cleanup_old_batch_jobs() - 오래된 작업 정리\n")
  cat("\n예시:\n")
  cat("  result <- run_batch_with_monitoring('code_check')\n")
  cat("  result <- resume_batch_monitoring('batches/xxxxx')\n")
}