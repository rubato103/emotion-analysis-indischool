# =============================================================================
# 추가 신뢰도 측정 함수들
# =============================================================================

# 가중 합의 지수 계산 함수
# 부분적 일치를 인정하는 신뢰도 측정
calculate_weighted_agreement_index <- function(coder_data, weights = c(1.0, 0.75, 0.5)) {
  log_message("INFO", "가중 합의 지수 계산 시작")
  
  if (missing(coder_data) || nrow(coder_data) == 0) {
    log_message("ERROR", "데이터가 제공되지 않았습니다.")
    return(list(weighted_index = NA, simple_agreement = NA, error = "데이터 없음"))
  }
  
  # 코더 응답 컬럼 추출
  coder_cols <- grep("human_agree_value", names(coder_data), value = TRUE)
  
  if (length(coder_cols) == 0) {
    log_message("ERROR", "코더 응답 컬럼을 찾을 수 없습니다.")
    return(list(weighted_index = NA, simple_agreement = NA, error = "컬럼 없음"))
  }
  
  log_message("INFO", sprintf("발견된 코더 컬럼: %s", paste(coder_cols, collapse = ", ")))
  
  tryCatch({
    n_coders <- length(coder_cols)
    n_items <- nrow(coder_data)
    
    # 각 항목별로 일치 패턴 분석
    agreement_scores <- numeric(n_items)
    agreement_patterns <- character(n_items)
    
    for (i in 1:n_items) {
      responses <- as.character(coder_data[i, coder_cols])
      response_table <- table(responses)
      
      # 응답 분포 계산
      max_count <- max(response_table)
      
      if (max_count == n_coders) {
        # 완전 일치 (4:0)
        agreement_scores[i] <- weights[1]
        agreement_patterns[i] <- sprintf("%d:0", n_coders)
      } else if (max_count == n_coders - 1) {
        # 다수 일치 (3:1)
        agreement_scores[i] <- weights[2]
        agreement_patterns[i] <- sprintf("%d:1", n_coders - 1)
      } else if (max_count == n_coders / 2) {
        # 분할 (2:2)
        agreement_scores[i] <- weights[3]
        agreement_patterns[i] <- "2:2"
      } else {
        # 기타 패턴
        agreement_scores[i] <- 0.25  # 최소 점수
        agreement_patterns[i] <- "기타"
      }
    }
    
    # 가중 평균 계산
    weighted_index <- mean(agreement_scores)
    
    # 단순 일치율 (완전 일치만)
    perfect_agreements <- sum(agreement_scores == weights[1])
    simple_agreement <- perfect_agreements / n_items
    
    # 패턴 분석
    pattern_summary <- table(agreement_patterns)
    
    log_message("INFO", sprintf("가중 합의 지수: %.3f (%.1f%%)", weighted_index, weighted_index * 100))
    log_message("INFO", sprintf("단순 일치율: %.3f (%.1f%%)", simple_agreement, simple_agreement * 100))
    log_message("INFO", sprintf("일치 패턴: %s", paste(names(pattern_summary), "=", pattern_summary, collapse = ", ")))
    
    return(list(
      weighted_index = weighted_index,
      simple_agreement = simple_agreement,
      pattern_summary = pattern_summary,
      weights_used = weights,
      n_items = n_items,
      n_coders = n_coders
    ))
    
  }, error = function(e) {
    log_message("ERROR", sprintf("가중 합의 지수 계산 실패: %s", e$message))
    return(list(weighted_index = NA, simple_agreement = NA, error = e$message))
  })
}

# 단순 일치율 계산 함수
# 우연 보정 없이 기본적인 합의 수준 측정
calculate_simple_agreement <- function(coder_data) {
  log_message("INFO", "단순 일치율 계산 시작")
  
  if (missing(coder_data) || nrow(coder_data) == 0) {
    log_message("ERROR", "데이터가 제공되지 않았습니다.")
    return(list(agreement_rate = NA, error = "데이터 없음"))
  }
  
  # 코더 응답 컬럼 추출
  coder_cols <- grep("human_agree_value", names(coder_data), value = TRUE)
  
  if (length(coder_cols) == 0) {
    log_message("ERROR", "코더 응답 컬럼을 찾을 수 없습니다.")
    return(list(agreement_rate = NA, error = "컬럼 없음"))
  }
  
  tryCatch({
    n_coders <- length(coder_cols)
    n_items <- nrow(coder_data)
    
    # 완전 일치 항목 계산
    perfect_agreements <- 0
    
    for (i in 1:n_items) {
      responses <- as.character(coder_data[i, coder_cols])
      if (length(unique(responses)) == 1) {
        perfect_agreements <- perfect_agreements + 1
      }
    }
    
    agreement_rate <- perfect_agreements / n_items
    
    # 각 코더별 TRUE 비율 계산 (참고용)
    coder_true_rates <- sapply(coder_cols, function(col) {
      mean(coder_data[[col]] == "TRUE", na.rm = TRUE)
    })
    
    log_message("INFO", sprintf("단순 일치율: %.3f (%.1f%%)", agreement_rate, agreement_rate * 100))
    log_message("INFO", sprintf("완전 일치 항목: %d/%d", perfect_agreements, n_items))
    
    return(list(
      agreement_rate = agreement_rate,
      perfect_agreements = perfect_agreements,
      n_items = n_items,
      n_coders = n_coders,
      coder_true_rates = coder_true_rates
    ))
    
  }, error = function(e) {
    log_message("ERROR", sprintf("단순 일치율 계산 실패: %s", e$message))
    return(list(agreement_rate = NA, error = e$message))
  })
}

# 순서형 Krippendorff's Alpha 계산 함수
# 순서가 있는 척도에서의 신뢰도 측정
calculate_ordinal_krippendorff_alpha <- function(coder_data) {
  log_message("INFO", "순서형 Krippendorff's Alpha 계산 시작")
  
  if (missing(coder_data) || nrow(coder_data) == 0) {
    log_message("ERROR", "데이터가 제공되지 않았습니다.")
    return(list(alpha = NA, interpretation = "데이터 없음", error = "데이터 없음"))
  }
  
  # 코더 응답 컬럼 추출
  coder_cols <- grep("human_agree_value", names(coder_data), value = TRUE)
  
  if (length(coder_cols) == 0) {
    log_message("ERROR", "코더 응답 컬럼을 찾을 수 없습니다.")
    return(list(alpha = NA, interpretation = "컬럼 없음", error = "컬럼 없음"))
  }
  
  tryCatch({
    # 논리값을 순서형으로 변환: FALSE = 1, TRUE = 2
    coder_matrix <- sapply(coder_cols, function(col) {
      as.numeric(factor(coder_data[[col]], levels = c("FALSE", "TRUE"), ordered = TRUE))
    })
    
    # 전치 (코더를 행으로)
    rater_matrix <- t(coder_matrix)
    
    # irr 패키지의 순서형 Alpha 계산
    alpha_result <- irr::kripp.alpha(rater_matrix, method = "ordinal")
    
    # 결과 해석
    alpha_value <- alpha_result$value
    interpretation <- if (is.na(alpha_value)) {
      "완전한 일치로 인한 계산 불가"
    } else if (alpha_value >= 0.8) {
      "매우 높은 신뢰도"
    } else if (alpha_value >= 0.667) {
      "높은 신뢰도"
    } else if (alpha_value >= 0.4) {
      "중간 신뢰도"
    } else {
      "낮은 신뢰도"
    }
    
    log_message("INFO", sprintf("순서형 Krippendorff's Alpha: %.3f (%s)", alpha_value %||% -999, interpretation))
    
    return(list(
      alpha = alpha_value,
      interpretation = interpretation,
      method = "ordinal",
      transformation = "FALSE=1, TRUE=2"
    ))
    
  }, error = function(e) {
    log_message("ERROR", sprintf("순서형 Alpha 계산 실패: %s", e$message))
    return(list(alpha = NA, interpretation = "계산 실패", error = e$message))
  })
}