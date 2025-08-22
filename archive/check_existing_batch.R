# 이미 생성된 배치 작업 확인 및 모니터링
# 방금 전 오류로 중단된 배치 작업을 확인합니다

source("config.R")
source("utils.R")
library(httr2)
library(jsonlite)

api_key <- Sys.getenv("GEMINI_API_KEY")

# 방금 전 로그에서 확인된 배치 이름
existing_batch_name <- "batches/5shd51qnqs81bs5ygo5341wchv8k6agj4hbx"

cat("=== 기존 배치 작업 확인 ===\n")
cat(sprintf("배치 이름: %s\n", existing_batch_name))

# 상태 확인
tryCatch({
  response <- httr2::request(sprintf("https://generativelanguage.googleapis.com/v1beta/%s", existing_batch_name)) %>%
    httr2::req_headers(`x-goog-api-key` = api_key) %>%
    httr2::req_perform()
  
  batch_status <- httr2::resp_body_json(response)
  
  cat("\n📊 배치 상태 정보:\n")
  cat(sprintf("상태: %s\n", batch_status$metadata$state))
  cat(sprintf("모델: %s\n", batch_status$metadata$model))
  cat(sprintf("생성일: %s\n", batch_status$metadata$createTime))
  cat(sprintf("수정일: %s\n", batch_status$metadata$updateTime))
  
  if (!is.null(batch_status$metadata$batchStats)) {
    stats <- batch_status$metadata$batchStats
    cat("\n📈 처리 통계:\n")
    cat(sprintf("총 요청: %s\n", stats$requestCount))
    cat(sprintf("대기 중: %s\n", stats$pendingRequestCount %||% "0"))
    cat(sprintf("성공: %s\n", stats$completedRequestCount %||% "0"))
    cat(sprintf("실패: %s\n", stats$failedRequestCount %||% "0"))
  }
  
  # 상태별 다음 행동 안내
  current_state <- batch_status$metadata$state
  
  cat("\n🎯 다음 단계:\n")
  
  if (current_state == "BATCH_STATE_PENDING") {
    cat("⏳ 배치가 처리 대기 중입니다.\n")
    cat("   - 몇 분 후 다시 확인하세요\n")
    cat("   - 또는 새로운 배치를 생성하세요\n")
    
  } else if (current_state == "BATCH_STATE_RUNNING") {
    cat("🔄 배치가 처리 중입니다.\n")
    cat("   - 완료까지 기다리거나\n")
    cat("   - batch_monitor.R로 모니터링하세요\n")
    
  } else if (current_state == "BATCH_STATE_SUCCEEDED") {
    cat("✅ 배치가 완료되었습니다!\n")
    cat("   - 결과를 다운로드할 수 있습니다\n")
    cat("   - batch_monitor.R > 4번 선택하여 다운로드\n")
    
  } else if (current_state == "BATCH_STATE_FAILED") {
    cat("❌ 배치가 실패했습니다.\n")
    cat("   - 새로운 배치를 생성하세요\n")
    
  } else {
    cat(sprintf("ℹ️ 알 수 없는 상태: %s\n", current_state))
  }
  
  cat("\n🔧 권장 행동:\n")
  cat("1. 이 배치 모니터링:\n")
  cat('   source("batch_monitor.R")\n')
  cat('   # 2번 선택 후 배치 이름 입력\n\n')
  
  cat("2. 새로운 파일럿 배치 생성:\n")
  cat('   source("04_배치처리_감정분석.R")\n')
  cat('   result <- run_batch_emotion_analysis("pilot")\n\n')
  
  cat("3. 완료된 경우 - 결과 다운로드:\n")
  cat('   source("batch_monitor.R")\n')
  cat('   # 4번 선택 후 배치 이름 입력\n')
  
}, error = function(e) {
  cat(sprintf("❌ 배치 상태 확인 실패: %s\n", e$message))
  cat("\n💡 이 경우 새로운 배치를 생성하는 것을 권장합니다:\n")
  cat('source("04_배치처리_감정분석.R")\n')
  cat('result <- run_batch_emotion_analysis("pilot")\n')
})

cat("\n=== 확인 완료 ===\n")