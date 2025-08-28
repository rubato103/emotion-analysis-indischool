# 데이터 구조 탐색 스크립트
# 목적: Parquet 파일들의 구조를 확인하고 비교

# 필요한 패키지 로드
library(arrow)
library(dplyr)

# 파일 경로 설정
prompt_file <- "data/prompts_ready.parquet"
result_file <- "results/analysis_results_code_check_20250828_203355.parquet"

# 1. 원데이터 (프롬프트 생성된 데이터) 구조 확인
cat("=== 원데이터 (prompts_ready.parquet) 구조 ===\n")
if (file.exists(prompt_file)) {
  # 메타데이터만 로드 (메모리 절약)
  prompt_meta <- arrow::read_parquet(prompt_file, as_data_frame = FALSE)
  cat("행 수:", nrow(prompt_meta), "\n")
  cat("열 수:", ncol(prompt_meta), "\n")
  cat("열 이름:", names(prompt_meta), "\n")
  cat("각 열의 데이터 타입:\n")
  print(str(prompt_meta))
  
  # 첫 몇 행만 로드하여 확인
  cat("\n첫 3행 샘플:\n")
  prompt_sample <- arrow::read_parquet(prompt_file, nrow = 3)
  print(prompt_sample)
} else {
  cat("파일을 찾을 수 없습니다:", prompt_file, "\n")
}

cat("\n", paste(rep("=", 50), collapse = ""), "\n")

# 2. 분석 결과 데이터 구조 확인
cat("=== 분석 결과 데이터 (analysis_results_code_check_*.parquet) 구조 ===\n")
if (file.exists(result_file)) {
  # 메타데이터만 로드 (메모리 절약)
  result_meta <- arrow::read_parquet(result_file, as_data_frame = FALSE)
  cat("행 수:", nrow(result_meta), "\n")
  cat("열 수:", ncol(result_meta), "\n")
  cat("열 이름:", names(result_meta), "\n")
  cat("각 열의 데이터 타입:\n")
  print(str(result_meta))
  
  # 첫 몇 행만 로드하여 확인
  cat("\n첫 3행 샘플:\n")
  result_sample <- arrow::read_parquet(result_file, nrow = 3)
  print(result_sample)
} else {
  cat("파일을 찾을 수 없습니다:", result_file, "\n")
  # 다른 결과 파일이 있는지 확인
  result_files <- list.files("results", pattern = "analysis_results.*\\.parquet$", full.names = TRUE)
  if (length(result_files) > 0) {
    cat("다른 분석 결과 파일들:\n")
    print(result_files)
  }
}

cat("\n=== 구조 비교 ===\n")
cat("프롬프트 데이터와 결과 데이터의 연결 관계를 분석합니다.\n")

# 두 데이터셋의 공통 열 확인 (연결 키)
if (file.exists(prompt_file) && file.exists(result_file)) {
  prompt_cols <- names(arrow::read_parquet(prompt_file, as_data_frame = FALSE))
  result_cols <- names(arrow::read_parquet(result_file, as_data_frame = FALSE))
  
  common_cols <- intersect(prompt_cols, result_cols)
  cat("공통 열 (연결 키로 사용될 수 있는 열):", common_cols, "\n")
  
  unique_to_prompt <- setdiff(prompt_cols, result_cols)
  cat("프롬프트 데이터에만 있는 열:", unique_to_prompt, "\n")
  
  unique_to_result <- setdiff(result_cols, prompt_cols)
  cat("결과 데이터에만 있는 열:", unique_to_result, "\n")
} else {
  cat("두 파일 모두 접근 가능할 때 구조 비교가 가능합니다.\n")
}