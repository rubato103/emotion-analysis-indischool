# 일반 분석 결과 구조 확인 스크립트
library(arrow)
library(dplyr)

# 일반 분석 결과 파일 로드
regular_result_file <- "results/analysis_results_code_check_20250828_203355.parquet"

if (file.exists(regular_result_file)) {
  cat("일반 분석 결과 파일 로드:", regular_result_file, "\n")
  
  # Parquet 파일 로드
  regular_df <- arrow::read_parquet(regular_result_file)
  
  cat("일반 분석 결과 구조:\n")
  str(regular_df)
  
  cat("\n열 이름:\n")
  print(names(regular_df))
  
  cat("\n처음 몇 행:\n")
  print(head(regular_df))
  
  # 배치 결과와 비교
  batch_result_file <- "results/batch_parsed_test.parquet"
  if (file.exists(batch_result_file)) {
    cat("\n배치 결과 파일 로드:", batch_result_file, "\n")
    batch_df <- arrow::read_parquet(batch_result_file)
    
    cat("배치 결과 구조:\n")
    str(batch_df)
    
    cat("\n열 이름:\n")
    print(names(batch_df))
    
    # 키 구조 확인
    if ("key" %in% names(batch_df)) {
      cat("\n배치 결과의 키 샘플:\n")
      print(head(batch_df$key))
      
      # 키에서 post_id와 comment_id 추출
      key_parts <- strsplit(batch_df$key[1], "_")
      cat("\n키 구조 예시:\n")
      print(key_parts)
    }
  }
} else {
  cat("일반 분석 결과 파일을 찾을 수 없습니다:", regular_result_file, "\n")
}