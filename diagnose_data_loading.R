# 배치 데이터 로딩 문제 진단
library(arrow)
library(dplyr)

# 원데이터 로드
cat("=== 원데이터 로드 진단 ===\n")
prompts_file <- "data/prompts_ready.parquet"
if (file.exists(prompts_file)) {
  cat("프롬프트 파일 존재함\n")
  prompts_df <- arrow::read_parquet(prompts_file)
  cat("원데이터 로드 성공: ", nrow(prompts_df), "행\n")
  
  # 샘플 데이터 확인
  cat("샘플 데이터:\n")
  print(head(prompts_df[c("post_id", "comment_id")]))
  
  # 특정 ID로 필터링
  test_post_id <- 37353082
  filtered_data <- prompts_df %>% filter(post_id == test_post_id)
  cat("post_id", test_post_id, "에 대한 데이터:", nrow(filtered_data), "행\n")
  
  if (nrow(filtered_data) > 0) {
    print(head(filtered_data[c("post_id", "comment_id")]))
  }
} else {
  cat("프롬프트 파일 없음:", prompts_file, "\n")
}

# 배치 결과 데이터 확인
cat("\n=== 배치 결과 데이터 확인 ===\n")
batch_files <- list.files("results", pattern = "batch_parsed_.*\\.RDS$", full.names = TRUE)
if (length(batch_files) > 0) {
  latest_batch <- batch_files[length(batch_files)]
  cat("최신 배치 파일:", basename(latest_batch), "\n")
  
  batch_data <- readRDS(latest_batch)
  cat("배치 데이터 항목 수:", length(batch_data), "\n")
  
  if (length(batch_data) > 0) {
    first_item <- batch_data[[1]]
    if (!is.null(first_item$key)) {
      cat("첫 번째 항목 키:", first_item$key, "\n")
      
      # 키에서 ID 추출
      key_parts <- strsplit(first_item$key, "_")[[1]]
      if (length(key_parts) >= 4) {
        post_id <- as.numeric(key_parts[2])
        comment_id <- as.numeric(key_parts[4])
        cat("추출된 ID - post_id:", post_id, ", comment_id:", comment_id, "\n")
      }
    }
  }
}

cat("\n=== 진단 완료 ===\n")