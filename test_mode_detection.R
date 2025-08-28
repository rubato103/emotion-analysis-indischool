# 배치 모드 감지 테스트
source("06_batch_monitor.R")

# 테스트 배치 이름
test_batch_name <- "batches/v54vae0nhoe5tmep1fqiiq1zoi7f62mxl8b0"

cat("테스트 배치 이름:", test_batch_name, "\n")

# 모드 감지 로직 테스트
selected_mode <- "batch_unknown"

# 개선된 로직
if (grepl("code_check", test_batch_name, ignore.case = TRUE)) {
  selected_mode <- "code_check"
} else if (grepl("pilot", test_batch_name, ignore.case = TRUE)) {
  selected_mode <- "pilot"
} else if (grepl("sampling", test_batch_name, ignore.case = TRUE)) {
  selected_mode <- "sampling"
} else if (grepl("full", test_batch_name, ignore.case = TRUE)) {
  selected_mode <- "full"
} else {
  # 배치 작업 목록에서 모드 정보 추출
  batch_jobs <- read_batch_jobs()
  if (!is.null(batch_jobs)) {
    cat("배치 작업 목록:\n")
    for (i in seq_along(batch_jobs)) {
      job <- batch_jobs[[i]]
      cat(sprintf("  %d. %s - %s 모드\n", i, job$batch_name, job$mode))
      if (grepl(test_batch_name, job$batch_name, fixed = TRUE) || 
          grepl(job$batch_name, test_batch_name, fixed = TRUE)) {
        selected_mode <- job$mode
        cat("  -> 매칭됨!\n")
        break
      }
    }
  }
  
  # 여전히 모드를 결정할 수 없는 경우 기본값 설정
  if (selected_mode == "batch_unknown") {
    selected_mode <- "code_check"  # 기본값으로 code_check 사용
    cat("모드를 결정할 수 없어 기본값(code_check) 사용\n")
  }
}

cat("결정된 모드:", selected_mode, "\n")