# 샘플 교체 시스템
# 과도한 샘플을 적절한 크기로 조정하는 함수들

# 샘플 교체 메인 함수
replace_oversized_sample <- function(analysis_results, target_size = 384, 
                                   max_size = 400, method = "random") {
  
  current_size <- nrow(analysis_results)
  
  # 크기 체크
  if (current_size <= max_size) {
    log_message("INFO", sprintf("샘플 크기(%d개)가 적절합니다. 교체 불필요.", current_size))
    return(analysis_results)
  }
  
  log_message("INFO", sprintf("샘플 크기(%d개)가 최대 허용치(%d개)를 초과합니다.", current_size, max_size))
  log_message("INFO", sprintf("샘플 교체를 시작합니다. (방법: %s)", method))
  
  # 교체 방법에 따른 처리
  if (method == "random") {
    replaced_sample <- random_replacement(analysis_results, max_size)
  } else if (method == "balanced") {
    replaced_sample <- balanced_replacement(analysis_results, max_size)
  } else if (method == "quality") {
    replaced_sample <- quality_replacement(analysis_results, max_size)
  } else {
    log_message("WARN", sprintf("알 수 없는 교체 방법: %s. 무작위 교체를 사용합니다.", method))
    replaced_sample <- random_replacement(analysis_results, max_size)
  }
  
  # 결과 검증
  final_size <- nrow(replaced_sample)
  
  if (final_size >= target_size && final_size <= max_size) {
    log_message("INFO", sprintf("샘플 교체 완료: %d개 → %d개", current_size, final_size))
    log_message("INFO", sprintf("목표(%d개) 달성 및 최대치(%d개) 준수", target_size, max_size))
  } else {
    log_message("WARN", sprintf("샘플 교체 후에도 조건 미충족. 크기: %d개", final_size))
  }
  
  return(replaced_sample)
}

# 1. 무작위 교체
random_replacement <- function(data, max_size) {
  log_message("INFO", "무작위 샘플 교체 수행 중...")
  
  return(data %>% sample_n(max_size))
}

# 2. 균형 교체 (게시글/댓글 비율 유지)
balanced_replacement <- function(data, max_size) {
  log_message("INFO", "균형 샘플 교체 수행 중...")
  
  # 원본 비율 계산
  original_composition <- data %>%
    count(구분) %>%
    mutate(ratio = n / nrow(data))
  
  log_message("INFO", "원본 구성 비율:")
  for(i in 1:nrow(original_composition)) {
    cat(sprintf("  %s: %.1f%%\n", 
                original_composition$구분[i], 
                original_composition$ratio[i] * 100))
  }
  
  # 비율에 따른 샘플링
  balanced_sample <- data %>%
    group_by(구분) %>%
    sample_n(size = min(n(), round(max_size * original_composition$ratio[match(구분[1], original_composition$구분)])), 
             replace = FALSE) %>%
    ungroup()
  
  # 부족한 경우 무작위로 추가
  current_size <- nrow(balanced_sample)
  if (current_size < max_size) {
    remaining_data <- data %>%
      anti_join(balanced_sample, by = names(data))
    
    additional_needed <- max_size - current_size
    if (nrow(remaining_data) >= additional_needed) {
      additional_sample <- remaining_data %>% sample_n(additional_needed)
      balanced_sample <- bind_rows(balanced_sample, additional_sample)
    }
  }
  
  return(balanced_sample)
}

# 3. 품질 기반 교체 (신뢰도 높은 분석 우선)
quality_replacement <- function(data, max_size) {
  log_message("INFO", "품질 기반 샘플 교체 수행 중...")
  
  # 품질 점수 계산
  quality_data <- data %>%
    mutate(
      # 신뢰도 점수 계산 (여러 기준 종합)
      confidence_score = case_when(
        dominant_emotion == "API 오류" ~ 0,
        is.na(dominant_emotion) ~ 0,
        dominant_emotion == "중립" ~ 0.7,  # 중립은 상대적으로 낮은 신뢰도
        TRUE ~ 1.0
      ),
      # 텍스트 길이 점수 (너무 짧거나 긴 것 제외)
      text_length = nchar(content),
      length_score = case_when(
        text_length < 10 ~ 0.3,
        text_length > 500 ~ 0.8,
        TRUE ~ 1.0
      ),
      # 종합 품질 점수
      quality_score = (confidence_score * 0.6) + (length_score * 0.4)
    ) %>%
    arrange(desc(quality_score), desc(text_length))
  
  # 상위 품질 샘플 선택
  quality_sample <- quality_data %>%
    slice_head(n = max_size) %>%
    select(-confidence_score, -text_length, -length_score, -quality_score)
  
  # 품질 분포 출력
  quality_stats <- quality_data %>%
    slice_head(n = max_size) %>%
    summarise(
      avg_confidence = mean(confidence_score, na.rm = TRUE),
      avg_text_length = mean(text_length, na.rm = TRUE),
      api_error_count = sum(dominant_emotion == "API 오류", na.rm = TRUE)
    )
  
  log_message("INFO", sprintf("선택된 샘플 품질: 평균 신뢰도 %.2f, 평균 길이 %.0f자, API 오류 %d건",
                              quality_stats$avg_confidence, 
                              quality_stats$avg_text_length,
                              quality_stats$api_error_count))
  
  return(quality_sample)
}

# 샘플 교체 결과 요약
print_replacement_summary <- function(original_data, replaced_data, method) {
  
  cat("\n", rep("=", 60), "\n")
  cat("🔄 샘플 교체 결과 요약\n")
  cat(rep("=", 60), "\n")
  
  original_stats <- original_data %>%
    count(구분) %>%
    mutate(비율 = round(n / nrow(original_data) * 100, 1))
  
  replaced_stats <- replaced_data %>%
    count(구분) %>%
    mutate(비율 = round(n / nrow(replaced_data) * 100, 1))
  
  cat("📊 교체 전:\n")
  for(i in 1:nrow(original_stats)) {
    cat(sprintf("   %s: %d개 (%.1f%%)\n", 
                original_stats$구분[i], original_stats$n[i], original_stats$비율[i]))
  }
  
  cat("\n🎯 교체 후:\n")
  for(i in 1:nrow(replaced_stats)) {
    cat(sprintf("   %s: %d개 (%.1f%%)\n", 
                replaced_stats$구분[i], replaced_stats$n[i], replaced_stats$비율[i]))
  }
  
  reduction_pct <- round((1 - nrow(replaced_data)/nrow(original_data)) * 100, 1)
  cat(sprintf("\n📉 샘플 감소: %d개 → %d개 (%.1f%% 감소)\n", 
              nrow(original_data), nrow(replaced_data), reduction_pct))
  
  cat(sprintf("🔧 사용된 방법: %s\n", method))
  
  # 게시글 정보
  original_posts <- original_data %>% filter(구분 == "게시글") %>% n_distinct(post_id)
  replaced_posts <- replaced_data %>% filter(구분 == "게시글") %>% n_distinct(post_id)
  
  cat(sprintf("\n📝 게시글 정보:\n"))
  cat(sprintf("   교체 전: %d개 게시글 → 교체 후: %d개 게시글\n", 
              original_posts, replaced_posts))
  
  cat(rep("=", 60), "\n\n")
}

# 대화형 교체 방법 선택
get_replacement_method <- function(current_size, max_size) {
  
  cat("\n", rep("=", 60), "\n")
  cat("🔄 샘플 크기 초과 - 교체 방법 선택\n")
  cat(rep("=", 60), "\n")
  
  cat(sprintf("현재 샘플: %d개 → 목표: %d개 이하\n\n", current_size, max_size))
  
  cat("1️⃣  무작위 교체 (Random)\n")
  cat("   - 빠르고 간단한 방법\n")
  cat("   - 모든 항목이 동일한 선택 확률\n\n")
  
  cat("2️⃣  균형 교체 (Balanced)\n")
  cat("   - 게시글/댓글 비율 유지\n")
  cat("   - 원본 구성과 유사한 분포\n\n")
  
  cat("3️⃣  품질 교체 (Quality)\n")
  cat("   - 신뢰도 높은 분석 우선 선택\n")
  cat("   - API 오류 항목 제외\n\n")
  
  while(TRUE) {
    choice <- readline("교체 방법을 선택하세요 (1: 무작위, 2: 균형, 3: 품질): ")
    
    if (choice == "1") {
      cat("✅ 무작위 교체 선택됨\n")
      return("random")
    } else if (choice == "2") {
      cat("✅ 균형 교체 선택됨\n")
      return("balanced")
    } else if (choice == "3") {
      cat("✅ 품질 교체 선택됨\n")
      return("quality")
    } else {
      cat("❌ 잘못된 선택입니다. 1, 2, 또는 3을 입력해주세요.\n")
    }
  }
}