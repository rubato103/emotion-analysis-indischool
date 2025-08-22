# 일반 분석과 배치 분석 결과 구조 비교

cat("=== 분석 결과 구조 비교 ===\n\n")

# 일반 분석 결과 (CODE_CHECK)
regular_result <- readRDS('results/analysis_results_CODE_CHECK_28items_20250724_090641.RDS')
cat("=== 일반 분석 결과 구조 ===\n")
cat("파일: analysis_results_CODE_CHECK_28items_20250724_090641.RDS\n")
cat("행 수:", nrow(regular_result), "\n")
cat("열 수:", ncol(regular_result), "\n")
cat("열 이름:\n")
print(names(regular_result))
cat("\n데이터 타입:\n")
print(sapply(regular_result, class))
cat("\n첫 번째 행 예시:\n")
print(head(regular_result, 1))

cat("\n\n=== 배치 분석 결과 구조 ===\n")
# 배치 분석 결과 (가장 최근 것)
batch_result <- readRDS('results/analysis_results_BATCH_CODE_CHECK_3items_20250724_091221.RDS')
cat("파일: analysis_results_BATCH_CODE_CHECK_3items_20250724_091221.RDS\n")
cat("행 수:", nrow(batch_result), "\n")
cat("열 수:", ncol(batch_result), "\n")
cat("열 이름:\n")
print(names(batch_result))
cat("\n데이터 타입:\n")
print(sapply(batch_result, class))
cat("\n첫 번째 행 예시:\n")
print(head(batch_result, 1))

cat("\n\n=== 구조 비교 결과 ===\n")
regular_cols <- names(regular_result)
batch_cols <- names(batch_result)

cat("일반 분석 전용 열:\n")
regular_only <- setdiff(regular_cols, batch_cols)
if (length(regular_only) > 0) {
  print(regular_only)
} else {
  cat("(없음)\n")
}

cat("배치 분석 전용 열:\n") 
batch_only <- setdiff(batch_cols, regular_cols)
if (length(batch_only) > 0) {
  print(batch_only)
} else {
  cat("(없음)\n")
}

cat("공통 열 개수:", length(intersect(regular_cols, batch_cols)), "\n")
cat("열 순서 동일 여부:", identical(regular_cols, batch_cols), "\n")

# 데이터 타입 비교
cat("\n=== 데이터 타입 비교 ===\n")
common_cols <- intersect(regular_cols, batch_cols)
type_differences <- 0
for (col in common_cols) {
  regular_type <- class(regular_result[[col]])
  batch_type <- class(batch_result[[col]])
  if (!identical(regular_type, batch_type)) {
    cat(sprintf("열 '%s': 일반분석=%s, 배치분석=%s\n", col, 
                paste(regular_type, collapse=","), 
                paste(batch_type, collapse=",")))
    type_differences <- type_differences + 1
  }
}

if (type_differences == 0) {
  cat("모든 공통 열의 데이터 타입이 동일합니다.\n")
}

cat("\n=== 요약 ===\n")
cat("총 열 개수 - 일반분석:", length(regular_cols), ", 배치분석:", length(batch_cols), "\n")
cat("구조 완전 동일 여부:", identical(regular_cols, batch_cols) && type_differences == 0, "\n")