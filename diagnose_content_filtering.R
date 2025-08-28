# 콘텐츠 필터링 문제 진단
library(arrow)
library(dplyr)
library(stringr)

# 원데이터 로드
cat("=== 콘텐츠 필터링 진단 ===\n")
prompts_file <- "data/prompts_ready.parquet"
if (file.exists(prompts_file)) {
  prompts_df <- arrow::read_parquet(prompts_file)
  
  # 특정 ID로 필터링
  test_post_id <- 37353082
  filtered_data <- prompts_df %>% filter(post_id == test_post_id)
  cat("post_id", test_post_id, "에 대한 데이터:", nrow(filtered_data), "행\n")
  
  if (nrow(filtered_data) > 0) {
    cat("\n콘텐츠 필터링 테스트:\n")
    
    # 필터링 전 데이터
    cat("필터링 전 행 수:", nrow(filtered_data), "\n")
    
    # content_cleaned 생성
    filtered_with_cleaned <- filtered_data %>%
      mutate(content_cleaned = trimws(content))
    
    # 각 필터 조건 테스트
    cat("NA 또는 빈 문자열:", sum(is.na(filtered_with_cleaned$content_cleaned) | filtered_with_cleaned$content_cleaned == ""), "행\n")
    cat("특정 문자열:", sum(filtered_with_cleaned$content_cleaned %in% c("내용 없음", "삭제된 댓글입니다.", "비밀 댓글입니다.")), "행\n")
    cat("삭제 메시지 포함:", sum(str_detect(filtered_with_cleaned$content_cleaned, "작성자가 (댓글|글)을 삭제하였습니다")), "행\n")
    cat("길이 2 이하:", sum(str_length(filtered_with_cleaned$content_cleaned) <= 2), "행\n")
    cat("한글/영문 미포함:", sum(!str_detect(filtered_with_cleaned$content_cleaned, "[가-힣A-Za-z]")), "행\n")
    
    # 전체 필터 적용
    filtered_final <- filtered_with_cleaned %>%
      filter(
        !(is.na(content_cleaned) | content_cleaned == "" |
          content_cleaned %in% c("내용 없음", "삭제된 댓글입니다.", "비밀 댓글입니다.") |
          str_detect(content_cleaned, "작성자가 (댓글|글)을 삭제하였습니다") |
          str_length(content_cleaned) <= 2 |
          !str_detect(content_cleaned, "[가-힣A-Za-z]"))
      )
    
    cat("필터링 후 행 수:", nrow(filtered_final), "\n")
    
    if (nrow(filtered_final) > 0) {
      cat("필터링된 데이터 샘플:\n")
      print(head(filtered_final[c("content", "content_cleaned")]))
    } else {
      cat("필터링 후 모든 데이터가 제거됨\n")
      cat("원본 데이터 샘플:\n")
      print(head(filtered_data[c("content")]))
    }
  }
}

cat("\n=== 진단 완료 ===\n")