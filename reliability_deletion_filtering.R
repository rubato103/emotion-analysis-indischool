# 신뢰도 분석을 위한 삭제 콘텐츠 필터링
# 목적: 인간 코딩과 AI 분석 비교 시 삭제된 콘텐츠 제외

library(arrow)
library(dplyr)
library(stringr)

# 삭제 콘텐츠 필터링 함수 (신뢰도 분석용)
filter_deleted_content_for_reliability <- function(data) {
  cat("=== 신뢰도 분석용 삭제 콘텐츠 필터링 ===
")
  cat("입력 데이터:", nrow(data), "행
")
  
  # 삭제된 콘텐츠 식별 마스크 생성
  deletion_masks <- list()
  
  # 1. 기본 삭제 메시지
  basic_deletion_messages <- c(
    "작성자가 댓글을 삭제하였습니다",
    "작성자가 글을 삭제하였습니다",  # 추가된 패턴
    "비밀 댓글입니다",
    "내용 없음",
    "다수의 신고 또는 커뮤니티 이용규정을 위반하여 차단된 게시물입니다"
  )
  
  deletion_masks$basic <- rep(FALSE, nrow(data))
  for (message in basic_deletion_messages) {
    mask <- str_detect(data$content, fixed(message))
    deletion_masks$basic <- deletion_masks$basic | mask
  }
  cat("기본 삭제 메시지:", sum(deletion_masks$basic), "건
")
  
  # 2. 탈퇴 회원
  deletion_masks$withdrawn <- str_detect(data$author, "탈퇴회원")
  cat("탈퇴 회원:", sum(deletion_masks$withdrawn), "건
")
  
  # 3. 빈 또는 무의미한 내용
  deletion_masks$empty <- is.na(data$content) | data$content == "" | str_trim(data$content) == ""
  cat("빈 내용:", sum(deletion_masks$empty), "건
")
  
  # 4. 매우 짧은 내용 (2자 이하)
  deletion_masks$too_short <- str_length(data$content) <= 2
  cat("2자 이하 내용:", sum(deletion_masks$too_short), "건
")
  
  # 5. 유효 문자 미포함
  deletion_masks$no_valid_chars <- !str_detect(data$content, "[가-힣A-Za-z]")
  cat("유효 문자 미포함:", sum(deletion_masks$no_valid_chars), "건
")
  
  # 종합 삭제 마스크
  total_deletion_mask <- Reduce("|", deletion_masks)
  cat("
총 삭제 대상:", sum(total_deletion_mask), "건
")
  cat("삭제 비율:", round(sum(total_deletion_mask) / nrow(data) * 100, 2), "%
")
  
  # 필터링된 데이터
  filtered_data <- data[!total_deletion_mask, ]
  cat("신뢰도 분석용 데이터:", nrow(filtered_data), "건
")
  
  # 필터링 정보 추가
  filtered_data$deletion_reason <- ""
  for (i in seq_along(deletion_masks)) {
    reason_name <- names(deletion_masks)[i]
    reason_mask <- deletion_masks[[i]]
    # 필터링된 데이터에는 적용되지 않으므로 실제 삭제된 데이터에만 적용
  }
  
  cat("=== 필터링 완료 ===

")
  
  # 필터링 요약 반환
  filtering_summary <- list(
    original_count = nrow(data),
    filtered_count = nrow(filtered_data),
    deleted_count = sum(total_deletion_mask),
    deletion_rate = sum(total_deletion_mask) / nrow(data),
    masks = deletion_masks,
    total_mask = total_deletion_mask
  )
  
  return(list(data = filtered_data, summary = filtering_summary))
}

# 인간 코딩 시트용 필터링 함수
prepare_human_coding_data <- function(data, sample_size = 400) {
  cat("=== 인간 코딩용 데이터 준비 ===
")
  
  # 1. 삭제 콘텐츠 필터링
  filtered_result <- filter_deleted_content_for_reliability(data)
  clean_data <- filtered_result$data
  
  # 2. 샘플링 (적응형 샘플링)
  if (nrow(clean_data) > sample_size) {
    # 게시글과 댓글의 균형을 맞춰 샘플링
    if ("구분" %in% names(clean_data)) {
      # 구분별로 균등 샘플링
      posts <- clean_data %>% filter(구분 == "게시글")
      comments <- clean_data %>% filter(구분 == "댓글")
      
      post_sample_size <- min(nrow(posts), round(sample_size * 0.3))  # 30%는 게시글
      comment_sample_size <- min(nrow(comments), sample_size - post_sample_size)
      
      sampled_posts <- if (nrow(posts) > 0) posts[sample(nrow(posts), post_sample_size), ] else posts[0, ]
      sampled_comments <- if (nrow(comments) > 0) comments[sample(nrow(comments), comment_sample_size), ] else comments[0, ]
      
      final_sample <- rbind(sampled_posts, sampled_comments)
    } else {
      # 랜덤 샘플링
      final_sample <- clean_data[sample(nrow(clean_data), sample_size), ]
    }
  } else {
    final_sample <- clean_data
  }
  
  cat("선정된 인간 코딩 샘플:", nrow(final_sample), "건
")
  if ("구분" %in% names(final_sample)) {
    cat("구분별 분포:
")
    print(table(final_sample$구분))
  }
  
  cat("=== 인간 코딩 데이터 준비 완료 ===

")
  
  return(final_sample)
}

# 테스트 실행
if (FALSE) {  # 실제 사용 시 TRUE로 변경
  # 원본 데이터 로드
  if (file.exists("data/data_collection.csv")) {
    corpus_df <- read.csv("data/data_collection.csv", stringsAsFactors = FALSE, fileEncoding = "UTF-8")
    
    # 신뢰도 분석용 필터링
    reliability_result <- filter_deleted_content_for_reliability(corpus_df)
    
    # 인간 코딩용 데이터 준비
    human_coding_sample <- prepare_human_coding_data(corpus_df, sample_size = 400)
    
    # 결과 저장
    if (!dir.exists("human_coding")) {
      dir.create("human_coding", recursive = TRUE)
    }
    
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    output_file <- paste0("human_coding/reliability_sample_", timestamp, ".parquet")
    arrow::write_parquet(human_coding_sample, output_file)
    cat("인간 코딩 샘플 저장 완료:", output_file, "
")
  }
}

# 삭제 패턴 상세 분석 함수
analyze_deletion_patterns <- function(data) {
  cat("=== 삭제 패턴 상세 분석 ===
")
  
  # content 컬럼에서 상위 삭제 관련 내용 분석
  deletion_related <- data %>%
    filter(!is.na(content)) %>%
    filter(str_detect(content, "삭제|탈퇴|비밀|차단|없음")) %>%
    count(content, sort = TRUE) %>%
    head(20)
  
  cat("상위 삭제 관련 내용 (상위 20개):
")
  print(deletion_related)
  
  # author 컬럼에서 탈퇴 관련 패턴 분석
  withdrawal_related <- data %>%
    filter(!is.na(author)) %>%
    filter(str_detect(author, "탈퇴|삭제|알수없는")) %>%
    count(author, sort = TRUE) %>%
    head(20)
  
  cat("
상위 탈퇴 관련 작성자 (상위 20개):
")
  print(withdrawal_related)
  
  cat("=== 삭제 패턴 분석 완료 ===

")
  
  return(list(
    deletion_content = deletion_related,
    withdrawal_authors = withdrawal_related
  ))
}