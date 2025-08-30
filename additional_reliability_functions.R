# 추가 신뢰도 분석 함수
# 삭제된 콘텐츠 필터링 및 Krippendorff's Alpha 계산

library(dplyr)
library(stringr)
library(irr)

#' 삭제된 콘텐츠 필터링 함수
#' 
#' @param data 인간 코딩 데이터
#' @return 필터링된 데이터와 요약 정보
filter_deleted_content_for_reliability <- function(data) {
  cat("=== 신뢰도 분석용 삭제 콘텐츠 필터링 ===\n")
  cat("입력 데이터:", nrow(data), "행\n")
  
  # 삭제된 콘텐츠 식별 마스크 생성
  deletion_masks <- list()
  
  # 1. 기본 삭제 메시지
  basic_deletion_messages <- c(
    "작성자가 댓글을 삭제하였습니다",
    "작성자가 글을 삭제하였습니다",
    "비밀 댓글입니다",
    "내용 없음",
    "다수의 신고 또는 커뮤니티 이용규정을 위반하여 차단된 게시물입니다"
  )
  
  deletion_masks$basic <- rep(FALSE, nrow(data))
  for (message in basic_deletion_messages) {
    mask <- str_detect(data$content, fixed(message))
    deletion_masks$basic <- deletion_masks$basic | mask
  }
  cat("기본 삭제 메시지:", sum(deletion_masks$basic), "건\n")
  
  # 2. 탈퇴 회원
  if ("author" %in% names(data)) {
    deletion_masks$withdrawn <- str_detect(data$author, "탈퇴회원")
    cat("탈퇴 회원:", sum(deletion_masks$withdrawn), "건\n")
  } else {
    deletion_masks$withdrawn <- rep(FALSE, nrow(data))
    cat("탈퇴 회원: author 컬럼 없음\n")
  }
  
  # 3. 빈 또는 무의미한 내용
  deletion_masks$empty <- is.na(data$content) | data$content == "" | str_trim(data$content) == ""
  cat("빈 내용:", sum(deletion_masks$empty), "건\n")
  
  # 4. 매우 짧은 내용 (2자 이하)
  deletion_masks$too_short <- str_length(data$content) <= 2
  cat("2자 이하 내용:", sum(deletion_masks$too_short), "건\n")
  
  # 5. 유효 문자 미포함
  deletion_masks$no_valid_chars <- !str_detect(data$content, "[가-힣A-Za-z]")
  cat("유효 문자 미포함:", sum(deletion_masks$no_valid_chars), "건\n")
  
  # 종합 삭제 마스크
  total_deletion_mask <- Reduce("|", deletion_masks)
  cat("\n총 삭제 대상:", sum(total_deletion_mask), "건\n")
  cat("삭제 비율:", round(sum(total_deletion_mask) / nrow(data) * 100, 2), "%\n")
  
  # 필터링된 데이터
  filtered_data <- data[!total_deletion_mask, ]
  cat("신뢰도 분석용 데이터:", nrow(filtered_data), "건\n")
  
  cat("=== 필터링 완료 ===\n\n")
  
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

#' 인간 코딩 데이터 준비 함수
#' 
#' @param data 원본 데이터
#' @param sample_size 샘플 크기
#' @return 인간 코딩용 샘플 데이터
prepare_human_coding_data <- function(data, sample_size = 400) {
  cat("=== 인간 코딩용 데이터 준비 ===\n")
  
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
  
  cat("선정된 인간 코딩 샘플:", nrow(final_sample), "건\n")
  if ("구분" %in% names(final_sample)) {
    cat("구분별 분포:\n")
    print(table(final_sample$구분))
  }
  
  cat("=== 인간 코딩 데이터 준비 완료 ===\n\n")
  
  return(final_sample)
}

#' 삭제 패턴 상세 분석 함수
#' 
#' @param data 데이터
#' @return 삭제 패턴 분석 결과
analyze_deletion_patterns <- function(data) {
  cat("=== 삭제 패턴 상세 분석 ===\n")
  
  # content 컬럼에서 상위 삭제 관련 내용 분석
  if ("content" %in% names(data)) {
    deletion_related <- data %>%
      filter(!is.na(content)) %>%
      filter(str_detect(content, "삭제|탈퇴|비밀|차단|없음")) %>%
      count(content, sort = TRUE) %>%
      head(20)
    
    cat("상위 삭제 관련 내용 (상위 20개):\n")
    print(deletion_related)
  }
  
  # author 컬럼에서 탈퇴 관련 패턴 분석
  if ("author" %in% names(data)) {
    withdrawal_related <- data %>%
      filter(!is.na(author)) %>%
      filter(str_detect(author, "탈퇴|삭제|알수없는")) %>%
      count(author, sort = TRUE) %>%
      head(20)
    
    cat("\n상위 탈퇴 관련 작성자 (상위 20개):\n")
    print(withdrawal_related)
  }
  
  cat("=== 삭제 패턴 분석 완료 ===\n\n")
}

#' 향상된 Krippendorff's Alpha 계산 함수
#' 
#' @param data_matrix 데이터 행렬
#' @param level 측정 수준 ("nominal", "ordinal", "interval", "ratio")
#' @param filter_deletion 삭제된 콘텐츠 필터링 여부
#' @return Alpha 값 및 해석
calculate_enhanced_kripp_alpha <- function(data_matrix, level = "interval", filter_deletion = TRUE) {
  cat("=== 향상된 Krippendorff's Alpha 계산 ===\n")
  
  # 삭제된 콘텐츠 필터링 (필요한 경우)
  if (filter_deletion) {
    cat("삭제된 콘텐츠 필터링 적용 중...\n")
    filtering_result <- filter_deleted_content_for_reliability(data_matrix)
    data_matrix <- filtering_result$data
    cat("필터링 결과:", filtering_result$summary$original_count, "->", filtering_result$summary$filtered_count, "건\n")
  }
  
  # 데이터 유효성 검사
  if (nrow(data_matrix) == 0) {
    log_message("WARN", "분석할 데이터가 없습니다.")
    return(list(alpha = NA, interpretation = "데이터 부족"))
  }
  
  cat(sprintf("🔄 Krippendorff's Alpha 계산 중... (%d개 항목, %d명 코더)\n", 
              nrow(data_matrix), ncol(data_matrix)))
  
  tryCatch({
    # 계산 시작 시간 기록
    start_time <- Sys.time()
    
    # 데이터 전치 (irr 패키지 요구사항)
    cat("  📊 데이터 전치 중...\n")
    transposed_data <- t(data_matrix)
    
    # irr 패키지의 kripp.alpha 함수 사용
    cat("  🧮 Alpha 값 계산 중...\n")
    result <- suppressWarnings(kripp.alpha(transposed_data, method = level))
    alpha_value <- result$value
    
    # 계산 완료 시간
    elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat(sprintf("  ✅ 계산 완료 (%.2f초 소요)\n", elapsed_time))
    
    # 해석 추가
    cat("  📋 결과 해석 중...\n")
    interpretation <- case_when(
      alpha_value >= 0.8 ~ "매우 높은 신뢰도 (Excellent)",
      alpha_value >= 0.67 ~ "높은 신뢰도 (Good)", 
      alpha_value >= 0.5 ~ "중간 신뢰도 (Moderate)",
      alpha_value >= 0.3 ~ "낮은 신뢰도 (Low)",
      TRUE ~ "매우 낮은 신뢰도 (Poor)"
    )
    
    cat(sprintf("  🎯 Alpha = %.3f (%s)\n", alpha_value, interpretation))
    
    return(list(
      alpha = alpha_value,
      interpretation = interpretation,
      n_items = nrow(data_matrix),
      n_raters = ncol(data_matrix),
      calculation_time = elapsed_time,
      filtered = filter_deletion
    ))
    
  }, error = function(e) {
    cat("  ❌ 계산 실패\n")
    log_message("ERROR", sprintf("Alpha 계산 실패: %s", e$message))
    return(list(alpha = NA, interpretation = "계산 실패", error = e$message))
  })
}