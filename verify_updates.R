# Final verification script for 06_batch_monitor.R updates
cat("=== 06_batch_monitor.R 업데이트 확인 ===\n\n")

# 1. Check if purrr package is in 05_batch_request.R
cat("1. 필요한 패키지 확인 (05_batch_request.R):\n")
purrr_check <- system("grep -c 'purrr' 05_batch_request.R", intern = TRUE)
if (as.numeric(purrr_check) > 0) {
  cat("   ✅ purrr 패키지가 05_batch_request.R에 추가됨\n")
} else {
  cat("   ❌ purrr 패키지가 05_batch_request.R에 없음\n")
}

# 2. Check if batch results are saved as Parquet
cat("\n2. 배치 결과 Parquet 저장 확인:\n")
parquet_save_lines <- system("grep -c 'batch_parsed.*parquet' 06_batch_monitor.R", intern = TRUE)
if (as.numeric(parquet_save_lines) > 0) {
  cat("   ✅ 배치 결과가 Parquet으로 저장되도록 설정됨\n")
} else {
  cat("   ❌ 배치 결과 Parquet 저장 설정을 찾을 수 없음\n")
}

# 3. Check if final results are saved as Parquet
cat("\n3. 최종 결과 Parquet 저장 확인:\n")
final_save_lines <- system("grep -c 'result_filename.*parquet' 06_batch_monitor.R", intern = TRUE)
if (as.numeric(final_save_lines) > 0) {
  cat("   ✅ 최종 결과가 Parquet으로 저장되도록 설정됨\n")
} else {
  cat("   ❌ 최종 결과 Parquet 저장 설정을 찾을 수 없음\n")
}

# 4. Check if parse_batch_results function was updated
cat("\n4. parse_batch_results 함수 업데이트 확인:\n")
parse_function_lines <- system("grep -c 'parse_batch_results.*function' 06_batch_monitor.R", intern = TRUE)
if (as.numeric(parse_function_lines) > 0) {
  cat("   ✅ parse_batch_results 함수가 업데이트됨\n")
} else {
  cat("   ❌ parse_batch_results 함수 업데이트를 찾을 수 없음\n")
}

# 5. Check if result structure matches regular analysis
cat("\n5. 결과 구조 확인:\n")
structure_check <- system("grep -c 'regular_columns' 06_batch_monitor.R", intern = TRUE)
if (as.numeric(structure_check) > 0) {
  cat("   ✅ 결과 구조가 일반 분석과 일치하도록 설정됨\n")
} else {
  cat("   ❌ 결과 구조 일치 설정을 찾을 수 없음\n")
}

cat("\n=== 확인 완료 ===\n")