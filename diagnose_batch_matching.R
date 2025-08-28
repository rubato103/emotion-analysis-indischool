# 배치 매칭 문제 진단 스크립트
library(arrow)
library(dplyr)

# 1. 원데이터 로드
cat("원데이터 로드 중...\n")
if (file.exists("data/prompts_ready.parquet")) {
  original_df <- arrow::read_parquet("data/prompts_ready.parquet")
  cat("원데이터: ", nrow(original_df), "행\n")
  
  # 샘플 데이터 확인
  cat("원데이터 샘플:\n")
  print(head(original_df[c("post_id", "comment_id")]))
} else {
  cat("원데이터 파일 없음\n")
  stop("원데이터 필요")
}

# 2. 배치 결과 로드
cat("\n배치 결과 로드 중...\n")
batch_result_file <- "results/batch_parsed_batch-v54vae0nhoe5tmep1fqiiq1zoi7f62mxl8b0_20250828_210849.RDS"
if (file.exists(batch_result_file)) {
  batch_df <- readRDS(batch_result_file)
  cat("배치 결과: ", length(batch_df), "개 항목\n")
  
  # 첫 번째 항목 확인
  if (length(batch_df) > 0) {
    first_item <- batch_df[[1]]
    cat("첫 번째 배치 항목의 구조:\n")
    str(first_item)
    
    # key 확인
    if (!is.null(first_item$key)) {
      cat("Key: ", first_item$key, "\n")
      
      # key에서 ID 추출
      key_parts <- strsplit(first_item$key, "_")[[1]]
      cat("Key parts: ", paste(key_parts, collapse = ", "), "\n")
    }
  }
} else {
  cat("배치 결과 파일 없음\n")
}

# 3. 키 기반 ID 추출 테스트
cat("\n키 기반 ID 추출 테스트:\n")
if (exists("batch_df") && length(batch_df) > 0) {
  # 모든 키 추출
  keys <- sapply(batch_df, function(x) if (!is.null(x$key)) x$key else NA)
  keys <- keys[!is.na(keys)]
  
  cat("Keys: ", paste(keys, collapse = ", "), "\n")
  
  # ID 추출
  post_ids <- sapply(strsplit(keys, "_"), function(parts) {
    if (length(parts) >= 4 && parts[1] == "post") {
      as.numeric(parts[2])
    } else {
      NA
    }
  })
  
  comment_ids <- sapply(strsplit(keys, "_"), function(parts) {
    if (length(parts) >= 4 && parts[3] == "comment") {
      as.numeric(parts[4])
    } else {
      NA
    }
  })
  
  cat("추출된 post_ids: ", paste(post_ids, collapse = ", "), "\n")
  cat("추출된 comment_ids: ", paste(comment_ids, collapse = ", "), "\n")
  
  # 원데이터에서 해당 ID 검색
  if (!is.na(post_ids[1]) && !is.na(comment_ids[1])) {
    matching_rows <- original_df %>%
      filter(post_id == post_ids[1] & comment_id == comment_ids[1])
    
    cat("매칭된 원데이터 행 수: ", nrow(matching_rows), "\n")
    if (nrow(matching_rows) > 0) {
      cat("매칭된 데이터:\n")
      print(matching_rows[c("post_id", "comment_id")])
    }
  }
}

cat("\n진단 완료!\n")