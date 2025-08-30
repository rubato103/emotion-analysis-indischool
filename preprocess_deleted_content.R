# 데이터 전처리 함수
# 목적: 삭제된 게시물/댓글을 필터링하여 분석 대상에서 제외

library(dplyr)
library(stringr)

#' 삭제된 콘텐츠 필터링 함수
#' 
#' @param data 원본 데이터 프레임 (data_collection.csv 로드된 데이터)
#' @return 필터링된 데이터 프레임
filter_deleted_content <- function(data) {
  cat("=== 삭제된 콘텐츠 필터링 시작 ===\n")
  cat("원본 데이터:", nrow(data), "행\n")
  
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
  cat("--- content 기반 필터링 ---\n")
  
  # 기본 삭제 메시지
  content_deletion_mask <- rep(FALSE, nrow(data))
  for (pattern in deletion_patterns$content_deletion) {
    mask <- str_detect(data$content, fixed(pattern))
    content_deletion_mask <- content_deletion_mask | mask
  }
  cat("기본 삭제 메시지:", sum(content_deletion_mask), "건\n")
  
  # 키워드 기반 삭제 콘텐츠
  content_keyword_mask <- rep(FALSE, nrow(data))
  for (pattern in deletion_patterns$content_keywords) {
    mask <- str_detect(data$content, pattern)
    content_keyword_mask <- content_keyword_mask | mask
  }
  cat("키워드 기반 삭제:", sum(content_keyword_mask), "건\n")
  
  # 2. author 기반 탈퇴 회원 필터링
  cat("--- author 기반 필터링 ---\n")
  
  withdrawal_mask <- rep(FALSE, nrow(data))
  for (pattern in deletion_patterns$author_withdrawal) {
    mask <- str_detect(data$author, pattern)
    withdrawal_mask <- withdrawal_mask | mask
  }
  cat("탈퇴 회원:", sum(withdrawal_mask), "건\n")
  
  # 3. 빈 내용 필터링
  cat("--- 빈 내용 필터링 ---\n")
  empty_mask <- is.na(data$content) | data$content == "" | str_trim(data$content) == ""
  cat("빈 내용:", sum(empty_mask), "건\n")
  
  # 4. 콘텐츠 길이 기반 필터링
  cat("--- 콘텐츠 길이 필터링 ---\n")
  short_content_mask <- str_length(data$content) <= 2
  cat("2자 이하 콘텐츠:", sum(short_content_mask), "건\n")
  
  # 5. 유효한 한글/영문 포함 여부 필터링
  cat("--- 유효 문자 포함 여부 필터링 ---\n")
  valid_text_mask <- !str_detect(data$content, "[가-힣A-Za-z]")
  cat("한글/영문 미포함:", sum(valid_text_mask), "건\n")
  
  # 종합 필터 마스크 생성
  cat("\n=== 종합 필터링 결과 ===\n")
  total_deletion_mask <- content_deletion_mask | content_keyword_mask | withdrawal_mask | 
                        empty_mask | short_content_mask | valid_text_mask
  
  cat("총 삭제 대상:", sum(total_deletion_mask), "건\n")
  cat("삭제 대상 비율:", round(sum(total_deletion_mask) / nrow(data) * 100, 2), "%\n")
  
  # 필터링된 데이터 반환
  filtered_data <- data[!total_deletion_mask, ]
  
  cat("\n필터링 후 데이터:", nrow(filtered_data), "행\n")
  cat("분석 대상 비율:", round(nrow(filtered_data) / nrow(data) * 100, 2), "%\n")
  cat("=== 삭제된 콘텐츠 필터링 완료 ===\n\n")
  
  return(filtered_data)
}

#' prompts_ready 데이터 생성 시 삭제된 콘텐츠 제외
#' 
#' @param input_csv 입력 CSV 파일 경로 (기본: "data/data_collection.csv")
#' @param output_file 출력 파일 경로 (기본: "data/prompts_ready_filtered.parquet")
#' @return 필터링 및 프롬프트 생성된 데이터
create_filtered_prompts <- function(input_csv = "data/data_collection.csv", 
                                   output_file = "data/prompts_ready_filtered.parquet") {
  
  # 1. 원본 데이터 로드
  cat("=== 프롬프트 생성 전처리 시작 ===\n")
  if (!file.exists(input_csv)) {
    stop("입력 파일을 찾을 수 없습니다: ", input_csv)
  }
  
  corpus_df <- read.csv(input_csv, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  cat("✅ 원본 데이터 로드 성공:", nrow(corpus_df), "행\n")
  
  # 2. 삭제된 콘텐츠 필터링
  filtered_corpus <- filter_deleted_content(corpus_df)
  
  # 3. 여기에 기존의 프롬프트 생성 로직을 적용할 수 있음
  # (01_data_loading_and_prompt_generation.R의 로직을 참고)
  
  cat("=== 프롬프트 생성 전처리 완료 ===\n")
  return(filtered_corpus)
}

# 테스트 실행
if (FALSE) {  # 실제 사용 시 TRUE로 변경
  # 데이터 전처리 테스트
  if (file.exists("data/data_collection.csv")) {
    filtered_data <- create_filtered_prompts()
    
    # 결과 요약
    cat("\n=== 전처리 결과 요약 ===\n")
    cat("필터링된 데이터:", nrow(filtered_data), "행\n")
    
    if ("구분" %in% names(filtered_data)) {
      cat("구분별 통계:\n")
      print(table(filtered_data$구분))
    }
    
    if ("depth" %in% names(filtered_data)) {
      cat("depth별 통계:\n")
      print(table(filtered_data$depth, useNA = "always"))
    }
    
    # 샘플 출력
    if (nrow(filtered_data) > 0) {
      cat("\n필터링된 데이터 샘플 (상위 5개):\n")
      print(head(filtered_data, 5))
    }
  }
}