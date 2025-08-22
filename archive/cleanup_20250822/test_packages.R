# 패키지 테스트 스크립트
log_file <- "package_test_log.txt"
cat("패키지 로딩 테스트 시작...\n", file = log_file)

# glue 패키지 테스트
tryCatch({
  library(glue)
  cat("✓ glue 패키지 로드 성공\n", file = log_file, append = TRUE)
  print("glue loaded successfully")
}, error = function(e) {
  cat("✗ glue 패키지 로드 실패:", e$message, "\n", file = log_file, append = TRUE)
  print(paste("glue error:", e$message))
})

# httr2 패키지 테스트
tryCatch({
  library(httr2)
  cat("✓ httr2 패키지 로드 성공\n", file = log_file, append = TRUE)
  print("httr2 loaded successfully")
}, error = function(e) {
  cat("✗ httr2 패키지 로드 실패:", e$message, "\n", file = log_file, append = TRUE)
  print(paste("httr2 error:", e$message))
})

cat("테스트 완료!\n", file = log_file, append = TRUE)
print("Test completed")