# 배치 결과와 원데이터 통합 스크립트
# 목적: 배치 결과를 원데이터 구조와 통합하여 일반 분석 결과와 동일한 구조로 저장

library(arrow)
library(dplyr)
library(jsonlite)

# 1. 원데이터 로드 (prompts_ready)
cat("원데이터 로드 중...\n")
original_data_file <- "data/prompts_ready.parquet"
if (file.exists(original_data_file)) {
  original_df <- arrow::read_parquet(original_data_file)
  cat("원데이터 로드 성공: ", nrow(original_df), "행, ", ncol(original_df), "열\n")
} else {
  cat("원데이터 파일을 찾을 수 없습니다:", original_data_file, "\n")
  stop("원데이터가 필요합니다")
}

# 2. 배치 결과 로드
cat("배치 결과 로드 중...\n")
batch_result_file <- "results/batch_parsed_test.parquet"
if (file.exists(batch_result_file)) {
  batch_df <- arrow::read_parquet(batch_result_file)
  cat("배치 결과 로드 성공: ", nrow(batch_df), "행, ", ncol(batch_df), "열\n")
} else {
  cat("배치 결과 파일을 찾을 수 없습니다:", batch_result_file, "\n")
  stop("배치 결과가 필요합니다")
}

# 3. 배치 결과의 키에서 post_id와 comment_id 추출
cat("키에서 ID 정보 추출 중...\n")
if ("key" %in% names(batch_df)) {
  # 키에서 post_id와 comment_id 추출
  key_parts <- strsplit(batch_df$key, "_")
  
  # 각 키를 파싱하여 post_id와 comment_id 추출
  post_ids <- sapply(key_parts, function(parts) {
    # "post_37353082_comment_0" 형식
    if (length(parts) >= 4 && parts[1] == "post") {
      as.numeric(parts[2])
    } else {
      NA
    }
  })
  
  comment_ids <- sapply(key_parts, function(parts) {
    # "post_37353082_comment_0" 형식
    if (length(parts) >= 4 && parts[3] == "comment") {
      as.numeric(parts[4])
    } else {
      NA
    }
  })
  
  # 배치 결과에 post_id와 comment_id 추가
  batch_df$post_id <- post_ids
  batch_df$comment_id <- comment_ids
  
  cat("ID 추출 완료: ", sum(!is.na(post_ids)), "개의 post_id, ", sum(!is.na(comment_ids)), "개의 comment_id\n")
} else {
  cat("배치 결과에 'key' 열이 없습니다.\n")
  stop("키 정보가 필요합니다")
}

# 4. 원데이터와 배치 결과 매칭
cat("원데이터와 배치 결과 매칭 중...\n")
# post_id와 comment_id를 기준으로 원데이터와 배치 결과 조인
matched_df <- original_df %>%
  # 배치 결과에 있는 데이터만 필터링
  semi_join(batch_df, by = c("post_id", "comment_id")) %>%
  # 배치 결과와 조인
  left_join(batch_df, by = c("post_id", "comment_id"))

cat("매칭 결과: ", nrow(matched_df), "행\n")

# 5. 일반 분석 결과 구조에 맞게 열 정리
cat("결과 구조 정리 중...\n")
# 일반 분석 결과의 열 순서와 이름 확인
regular_columns <- c(
  "post_id", "comment_id", "page_url", "depth", "구분", "title", "author", "date", 
  "views", "likes", "content", "prompt", "chunk_id",
  "기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대",
  "P", "A", "D", 
  "emotion_source", "emotion_direction", 
  "combinated_emotion", "complex_emotion", "rationale", "error_message"
)

# 배치 결과에 없는 열 추가 (일반 분석 결과와 구조 맞춤)
if (!"chunk_id" %in% names(matched_df)) {
  matched_df$chunk_id <- 1
}

# 열 순서 정리 및 누락된 열 처리
final_df <- matched_df %>%
  select(all_of(intersect(regular_columns, names(.))), 
         any_of(setdiff(regular_columns, names(.)))) %>%
  # 누락된 열이 있다면 기본값으로 추가
  mutate(
    chunk_id = ifelse(is.na(chunk_id), 1, chunk_id),
    error_message = ifelse(is.na(error_message), NA_character_, error_message)
  )

# 열 순서를 일반 분석 결과와 동일하게 맞춤
if (all(regular_columns %in% names(final_df))) {
  final_df <- final_df[, regular_columns]
}

cat("최종 결과 구조:\n")
str(final_df)

# 6. 결과 저장
cat("결과 저장 중...\n")
output_file <- "results/batch_integrated_result.parquet"
tryCatch({
  arrow::write_parquet(final_df, output_file, compression = "snappy")
  cat("✅ 통합 결과 저장 성공:", output_file, "\n")
  
  # 저장된 파일 확인
  saved_df <- arrow::read_parquet(output_file)
  cat("저장된 파일 구조 확인:\n")
  cat("행 수:", nrow(saved_df), "\n")
  cat("열 수:", ncol(saved_df), "\n")
  cat("열 이름:", names(saved_df), "\n")
  
  # 처음 몇 행 표시
  cat("\n처음 몇 행:\n")
  print(head(saved_df))
}, error = function(e) {
  cat("❌ 결과 저장 실패:", e$message, "\n")
})

cat("\n통합 완료!\n")