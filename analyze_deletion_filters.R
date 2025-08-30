# 삭제된 콘텐츠 필터링 분석
# 목적: 프롬프트 생성 시 삭제된 게시물/댓글을 제외하는 필터 개발

library(arrow)
library(dplyr)
library(stringr)

cat("=== 삭제된 콘텐츠 필터링 분석 ===\n")

# 원본 데이터 로드
if (file.exists("data/data_collection.csv")) {
  corpus_df <- read.csv("data/data_collection.csv", stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  cat("✅ 원본 데이터 로드 성공:", nrow(corpus_df), "행\n")
  
  # 삭제된 콘텐츠 패턴 정의
  deletion_patterns <- list(
    # content 기반 삭제 패턴
    content_deletion = c(
      "작성자가 댓글을 삭제하였습니다",
      "비밀 댓글입니다",
      "내용 없음",
      "다수의 신고 또는 커뮤니티 이용규정을 위반하여 차단된 게시물입니다",
      "삭제된 댓글입니다",
      "삭제된 게시글입니다"
    ),
    
    # content에 포함되는 삭제 관련 키워드
    content_keywords = c(
      "삭제되었습니다",
      "삭제 되었습니다",
      "삭제됨",
      "삭제되어",
      "삭제하였습니다",
      "삭제했습니다",
      "삭제합니다",
      "삭제하겠습니다",
      "삭제 예정",
      "삭제 요청",
      "삭제 조치"
    ),
    
    # author 기반 탈퇴 회원 패턴
    author_withdrawal = c(
      "탈퇴회원",
      "탈퇴 회원",
      "탈퇴.*계정",
      "알수없는.*사용자",
      "알 수 없는.*사용자",
      "삭제된.*사용자",
      "탈퇴.*사용자"
    )
  )
  
  # 1. content 기반 삭제 콘텐츠 필터링
  cat("\n--- content 기반 삭제 콘텐츠 분석 ---\n")
  
  # 기본 삭제 메시지
  content_deletion_mask <- rep(FALSE, nrow(corpus_df))
  for (pattern in deletion_patterns$content_deletion) {
    mask <- str_detect(corpus_df$content, fixed(pattern))
    content_deletion_mask <- content_deletion_mask | mask
    if (sum(mask) > 0) {
      cat(sprintf("'%s': %d건\n", pattern, sum(mask)))
    }
  }
  
  # 키워드 기반 삭제 콘텐츠
  content_keyword_mask <- rep(FALSE, nrow(corpus_df))
  for (pattern in deletion_patterns$content_keywords) {
    mask <- str_detect(corpus_df$content, pattern)
    content_keyword_mask <- content_keyword_mask | mask
    if (sum(mask) > 0) {
      cat(sprintf("'%s': %d건\n", pattern, sum(mask)))
    }
  }
  
  # 2. author 기반 탈퇴 회원 필터링
  cat("\n--- author 기반 탈퇴 회원 분석 ---\n")
  
  withdrawal_mask <- rep(FALSE, nrow(corpus_df))
  for (pattern in deletion_patterns$author_withdrawal) {
    mask <- str_detect(corpus_df$author, pattern)
    withdrawal_mask <- withdrawal_mask | mask
    if (sum(mask) > 0) {
      cat(sprintf("'%s': %d건\n", pattern, sum(mask)))
    }
  }
  
  # 3. 빈 내용 필터링
  cat("\n--- 빈 내용 분석 ---\n")
  empty_mask <- is.na(corpus_df$content) | corpus_df$content == "" | str_trim(corpus_df$content) == ""
  cat("빈 내용:", sum(empty_mask), "건\n")
  
  # 4. 콘텐츠 길이 기반 필터링
  cat("\n--- 콘텐츠 길이 분석 ---\n")
  corpus_df$content_length <- str_length(corpus_df$content)
  short_content_mask <- corpus_df$content_length <= 2
  cat("2자 이하 콘텐츠:", sum(short_content_mask), "건\n")
  
  # 5. 유효한 한글/영문 포함 여부
  cat("\n--- 유효 문자 포함 여부 ---\n")
  valid_text_mask <- !str_detect(corpus_df$content, "[가-힣A-Za-z]")
  cat("한글/영문 미포함:", sum(valid_text_mask), "건\n")
  
  # 종합 필터 마스크 생성
  cat("\n=== 종합 필터링 결과 ===\n")
  total_deletion_mask <- content_deletion_mask | content_keyword_mask | withdrawal_mask | 
                        empty_mask | short_content_mask | valid_text_mask
  
  cat("총 삭제 대상:", sum(total_deletion_mask), "건\n")
  cat("삭제 대상 비율:", round(sum(total_deletion_mask) / nrow(corpus_df) * 100, 2), "%\n")
  
  # 구분별 삭제 대상
  if ("구분" %in% names(corpus_df)) {
    cat("\n구분별 삭제 대상:\n")
    deletion_by_type <- corpus_df %>%
      mutate(is_deleted = total_deletion_mask) %>%
      group_by(구분) %>%
      summarise(
        total = n(),
        deleted = sum(is_deleted),
        deletion_rate = round(sum(is_deleted) / n() * 100, 2)
      )
    print(deletion_by_type)
  }
  
  # depth별 삭제 대상
  if ("depth" %in% names(corpus_df)) {
    cat("\ndepth별 삭제 대상:\n")
    deletion_by_depth <- corpus_df %>%
      mutate(is_deleted = total_deletion_mask) %>%
      group_by(depth) %>%
      summarise(
        total = n(),
        deleted = sum(is_deleted),
        deletion_rate = round(sum(is_deleted) / n() * 100, 2)
      )
    print(deletion_by_depth)
  }
  
  # 샘플 데이터 확인
  cat("\n=== 삭제 대상 샘플 ===\n")
  deleted_samples <- corpus_df[total_deletion_mask, ]
  if (nrow(deleted_samples) > 0) {
    cat("삭제 대상 상위 10개 샘플:\n")
    sample_size <- min(10, nrow(deleted_samples))
    for (i in 1:sample_size) {
      cat(sprintf("\n%d. [구분: %s, depth: %s]\n", i, 
                  deleted_samples$구분[i], 
                  ifelse(is.na(deleted_samples$depth[i]), "NA", deleted_samples$depth[i])))
      cat(sprintf("   author: %s\n", deleted_samples$author[i]))
      content_preview <- substr(deleted_samples$content[i], 1, 100)
      if (nchar(deleted_samples$content[i]) > 100) {
        content_preview <- paste0(content_preview, "...")
      }
      cat(sprintf("   content: %s\n", content_preview))
      
      # 어떤 필터에 걸렸는지 표시
      reasons <- c()
      if (content_deletion_mask[which(total_deletion_mask)[i]]) reasons <- c(reasons, "기본삭제메시지")
      if (content_keyword_mask[which(total_deletion_mask)[i]]) reasons <- c(reasons, "삭제키워드")
      if (withdrawal_mask[which(total_deletion_mask)[i]]) reasons <- c(reasons, "탈퇴회원")
      if (empty_mask[which(total_deletion_mask)[i]]) reasons <- c(reasons, "빈내용")
      if (short_content_mask[which(total_deletion_mask)[i]]) reasons <- c(reasons, "짧은내용")
      if (valid_text_mask[which(total_deletion_mask)[i]]) reasons <- c(reasons, "유효문자없음")
      
      cat(sprintf("   삭제사유: %s\n", paste(reasons, collapse=", ")))
    }
  }
  
  # 필터링 후 남는 데이터 수
  remaining_data <- corpus_df[!total_deletion_mask, ]
  cat(sprintf("\n=== 필터링 결과 ===\n"))
  cat(sprintf("원본 데이터: %d건\n", nrow(corpus_df)))
  cat(sprintf("삭제 대상: %d건 (%.2f%%)\n", sum(total_deletion_mask), 
              sum(total_deletion_mask) / nrow(corpus_df) * 100))
  cat(sprintf("분석 대상: %d건 (%.2f%%)\n", nrow(remaining_data), 
              nrow(remaining_data) / nrow(corpus_df) * 100))
  
  # prompts_ready 파일과 비교
  if (file.exists("data/prompts_ready.parquet")) {
    prompts_df <- arrow::read_parquet("data/prompts_ready.parquet")
    cat(sprintf("\n현재 prompts_ready 데이터: %d건\n", nrow(prompts_df)))
    cat(sprintf("필터링 후 데이터 차이: %d건\n", nrow(prompts_df) - nrow(remaining_data)))
  }
  
} else {
  cat("❌ 원본 데이터 파일을 찾을 수 없습니다.\n")
}

cat("\n=== 분석 완료 ===\n")