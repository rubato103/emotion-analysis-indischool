# 배치 모니터 테스트 스크립트
# 목적: 수정된 06_batch_monitor.R가 정상 작동하는지 확인

# 간단한 테스트만 수행
cat("=== 06_batch_monitor.R 테스트 ===\n")

# 스크립트 로드 테스트
tryCatch({
  source("06_batch_monitor.R")
  cat("✅ 06_batch_monitor.R 로드 성공\n")
  
  # BatchMonitor 클래스 초기화 테스트
  monitor <- BatchMonitor$new()
  cat("✅ BatchMonitor 클래스 초기화 성공\n")
  
  # 함수 존재 여부 확인
  if (exists("parse_batch_results", where = monitor)) {
    cat("✅ parse_batch_results 함수 존재\n")
  } else {
    cat("❌ parse_batch_results 함수 없음\n")
  }
  
  cat("=== 테스트 완료 ===\n")
  
}, error = function(e) {
  cat("❌ 테스트 실패:", e$message, "\n")
  cat("=== 테스트 완료 (오류 발생) ===\n")
})