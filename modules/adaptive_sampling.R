# 적응형 샘플링 함수
# 게시글-댓글 맥락을 유지하면서 목표 샘플 수 달성

# 적응형 샘플링 메인 함수
adaptive_sampling <- function(data, target_size = 384, min_posts = 2, 
                            max_posts = 1000, max_iterations = 10, 
                            increment_step = 5, safety_buffer = 0.15) {
  
  # 안전 버퍼를 고려한 실제 목표 설정 (필터링 손실 대비)
  buffered_target <- ceiling(target_size * (1 + safety_buffer))
  log_message("INFO", sprintf("적응형 샘플링 시작 - 목표: %d개 (버퍼 포함: %d개)", target_size, buffered_target))
  
  # 전체 게시글 ID 목록
  all_post_ids <- data %>%
    filter(구분 == "게시글") %>%
    distinct(post_id) %>%
    pull(post_id)
  
  total_posts <- length(all_post_ids)
  log_message("INFO", sprintf("전체 게시글 수: %d개", total_posts))
  
  # 목표 달성 불가능한 경우 체크
  total_items <- nrow(data)
  if (total_items < buffered_target) {
    log_message("WARN", sprintf("전체 데이터(%d개)가 버퍼 목표(%d개)보다 작습니다. 전체 데이터를 반환합니다.", 
                                total_items, buffered_target))
    return(data)
  }
  
  current_posts <- min_posts
  iteration <- 1
  
  while (iteration <= max_iterations && current_posts <= min(max_posts, total_posts)) {
    
    log_message("INFO", sprintf("반복 %d: %d개 게시글로 시도", iteration, current_posts))
    
    # 현재 게시글 수만큼 무작위 선택
    selected_post_ids <- sample(all_post_ids, min(current_posts, total_posts))
    
    # 선택된 게시글과 관련 댓글 추출
    sampled_data <- data %>%
      filter(post_id %in% selected_post_ids) %>%
      arrange(post_id, 구분, comment_id)
    
    current_size <- nrow(sampled_data)
    
    # 게시글/댓글 구성 출력
    composition <- sampled_data %>%
      count(구분) %>%
      mutate(비율 = round(n / current_size * 100, 1))
    
    log_message("INFO", sprintf("현재 샘플 크기: %d개", current_size))
    cat("  구성: ")
    for(i in 1:nrow(composition)) {
      cat(sprintf("%s %d개(%.1f%%) ", 
                  composition$구분[i], composition$n[i], composition$비율[i]))
    }
    cat("\n")
    
    # 목표 달성 체크 (버퍼 목표 기준)
    if (current_size >= buffered_target) {
      log_message("INFO", sprintf("버퍼 목표 달성! %d개 게시글로 %d개 샘플 확보", 
                                  current_posts, current_size))
      
      # 최종 목표보다 많이 확보했는지 확인
      if (current_size >= target_size) {
        log_message("INFO", sprintf("최종 목표(%d개) 초과 달성: %d개", target_size, current_size))
        return(sampled_data)
      } else {
        log_message("WARN", sprintf("버퍼 목표는 달성했지만 최종 목표(%d개) 미달. 계속 진행...", target_size))
      }
    }
    
    # 다음 반복을 위한 게시글 수 증가
    current_posts <- current_posts + increment_step
    iteration <- iteration + 1
    
    # 전체 게시글을 다 사용했는데 목표 미달성시
    if (current_posts > total_posts && current_size < buffered_target) {
      log_message("WARN", sprintf("모든 게시글(%d개)을 사용해도 버퍼 목표(%d개) 미달성. 현재 샘플(%d개)을 반환합니다.", 
                                  total_posts, buffered_target, current_size))
      if (current_size >= target_size) {
        log_message("INFO", sprintf("하지만 최종 목표(%d개)는 달성했습니다.", target_size))
      }
      return(sampled_data)
    }
  }
  
  # 최대 반복 초과시 - 조정은 03 스크립트에서 처리
  final_size <- nrow(sampled_data)
  
  log_message("WARN", sprintf("최대 반복(%d회) 초과. 샘플(%d개)을 반환합니다.", 
                              max_iterations, final_size))
  
  if (final_size >= target_size) {
    log_message("INFO", sprintf("목표(%d개) 달성: %d개", target_size, final_size))
  } else {
    log_message("WARN", sprintf("목표(%d개) 미달성: %d개 (%.1f%% 달성)", 
                                target_size, final_size, (final_size/target_size)*100))
  }
  
  return(sampled_data)
}

# 4단계 분석 모드 선택 인터페이스
get_analysis_mode <- function() {
  
  cat("\n", rep("=", 70), "\n")
  cat("🔬 감정분석 실행 모드 선택 (4단계 시스템 + 배치 처리)\n")
  cat(rep("=", 70), "\n")
  
  cat("1️⃣  코드 점검 (Code Check)\n")
  cat("   - 목표: 1개 게시물 (게시글+댓글)\n")
  cat("   - 용도: 프롬프트 및 코드 검증\n")
  cat("   - 시간: 30초-1분 소요\n")
  cat("   - 인간 코딩: 생략\n\n")
  
  cat("2️⃣  파일럿 연구 (Pilot Study)\n")
  cat("   - 목표: 5개 게시물 (게시글+댓글)\n")
  cat("   - 용도: 예비 분석 및 방법론 검증\n")
  cat("   - 시간: 2-5분 소요\n")
  cat("   - 인간 코딩: 선택적 실행\n\n")
  
  cat("3️⃣  표본 분석 (Sampling Analysis)\n")
  cat("   - 목표: 384개 이상 샘플 (통계적 유의성)\n")
  cat("   - 용도: 본격적인 연구 분석\n")
  cat("   - 적응형 샘플링 사용\n")
  cat("   - 인간 코딩: 필수 실행\n\n")
  
  cat("4️⃣  전체 분석 (Full Analysis)\n")
  cat("   - 목표: 모든 데이터 분석\n")
  cat("   - 용도: 완전한 데이터셋 분석\n")
  cat("   - 시간/비용: 매우 높음\n")
  cat("   - 인간 코딩: 표본 기반 검증\n\n")
  
  cat("💰 배치 처리 모드 (Batch Processing)\n")
  cat(sprintf("5️⃣  배치 코드점검    - %d%% 할인, %d시간내 처리\n", 
             BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
  cat(sprintf("6️⃣  배치 파일럿      - %d%% 할인, %d시간내 처리\n", 
             BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
  cat(sprintf("7️⃣  배치 표본분석    - %d%% 할인, %d시간내 처리\n", 
             BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
  cat(sprintf("8️⃣  배치 전체분석    - %d%% 할인, %d시간내 처리\n", 
             BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
  cat("\n")
  
  cat("🔍 배치 작업 관리\n")
  cat("9️⃣  배치 작업 모니터링 - 진행중인 배치 작업 확인/관리\n\n")
  
  while(TRUE) {
    choice <- readline("선택하세요 (1-4: 즉시처리, 5-8: 배치처리, 9: 모니터링): ")
    
    if (choice == "1") {
      cat("🔧 코드 점검 모드 선택됨\n")
      return("code_check")
    } else if (choice == "2") {
      cat("🧪 파일럿 연구 모드 선택됨\n")
      return("pilot")
    } else if (choice == "3") {
      cat("📊 표본 분석 모드 선택됨\n")
      return("sampling")
    } else if (choice == "4") {
      confirm <- readline("⚠️  전체 분석은 시간과 비용이 매우 많이 듭니다. 계속하시겠습니까? (y/N): ")
      if (tolower(confirm) %in% c("y", "yes", "ㅇ")) {
        cat("🌍 전체 분석 모드 선택됨\n")
        return("full")
      } else {
        cat("❌ 전체 분석이 취소되었습니다. 다시 선택해주세요.\n\n")
      }
    } else if (choice == "5") {
      cat(sprintf("💰 배치 코드점검 모드 선택됨 (%d%% 할인, %d시간 내 처리)\n", 
                  BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
      return("batch_code_check")
    } else if (choice == "6") {
      cat(sprintf("💰 배치 파일럿 모드 선택됨 (%d%% 할인, %d시간 내 처리)\n", 
                  BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
      return("batch_pilot")
    } else if (choice == "7") {
      cat(sprintf("💰 배치 표본분석 모드 선택됨 (%d%% 할인, %d시간 내 처리)\n", 
                  BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
      return("batch_sampling")
    } else if (choice == "8") {
      confirm <- readline("⚠️  배치 전체분석도 여전히 비용이 높습니다. 계속하시겠습니까? (y/N): ")
      if (tolower(confirm) %in% c("y", "yes", "ㅇ")) {
        cat(sprintf("💰 배치 전체분석 모드 선택됨 (%d%% 할인, %d시간 내 처리)\n", 
                    BATCH_CONFIG$cost_savings_percentage, BATCH_CONFIG$expected_processing_hours))
        return("batch_full")
      } else {
        cat("❌ 배치 전체분석이 취소되었습니다. 다시 선택해주세요.\n\n")
      }
    } else if (choice == "9") {
      cat("🔍 배치 작업 모니터링 모드 선택됨\n")
      return("batch_monitor")
    } else {
      cat("❌ 잘못된 선택입니다. 1-9 중에서 선택해주세요.\n")
    }
  }
}

# 4단계 모드별 샘플링 함수
get_sample_for_mode <- function(data, mode) {
  
  total_posts <- data %>% filter(구분 == "게시글") %>% nrow()
  total_items <- nrow(data)
  
  cat(sprintf("전체 데이터: %d개 게시글, %d개 항목\n", total_posts, total_items))
  
  if (mode == "code_check") {
    # 코드 점검: 1개 게시물
    target_posts <- min(1, total_posts)  # 정확히 1개 게시글
    
    selected_post_ids <- data %>%
      filter(구분 == "게시글") %>%
      sample_n(target_posts) %>%
      pull(post_id)
    
    sampled_data <- data %>%
      filter(post_id %in% selected_post_ids) %>%
      arrange(post_id, 구분, comment_id)
    
    cat(sprintf("🔧 코드 점검: %d개 게시글 → %d개 항목\n", target_posts, nrow(sampled_data)))
    
  } else if (mode == "pilot") {
    # 파일럿: 5개 게시물
    target_posts <- min(5, total_posts)  # 정확히 5개 게시글
    
    selected_post_ids <- data %>%
      filter(구분 == "게시글") %>%
      sample_n(target_posts) %>%
      pull(post_id)
    
    sampled_data <- data %>%
      filter(post_id %in% selected_post_ids) %>%
      arrange(post_id, 구분, comment_id)
    
    cat(sprintf("🧪 파일럿 연구: %d개 게시글 → %d개 항목\n", target_posts, nrow(sampled_data)))
    
  } else if (mode == "sampling") {
    # 표본 분석: 적응형 샘플링 사용
    cat("📊 적응형 샘플링 시작...\n")
    sampled_data <- adaptive_sampling(
      data = data,
      target_size = 384,
      min_posts = 5,
      max_posts = min(100, total_posts),
      max_iterations = 15,
      increment_step = 5,
      safety_buffer = 0.15
    )
    
  } else if (mode == "full") {
    # 전체 분석: 모든 데이터
    sampled_data <- data
    cat(sprintf("🌍 전체 분석: 모든 데이터 (%d개 항목)\n", nrow(sampled_data)))
    
  } else {
    stop("Unknown analysis mode: ", mode)
  }
  
  return(sampled_data)
}

# 샘플링 결과 요약 출력
print_sampling_summary <- function(original_data, sampled_data, mode) {
  
  cat("\n", rep("=", 70), "\n")
  cat("📈 분석 결과 요약\n")
  cat(rep("=", 70), "\n")
  
  # 모드별 아이콘 및 제목
  mode_info <- switch(mode,
    "code_check" = list(icon = "🔧", name = "코드 점검"),
    "pilot" = list(icon = "🧪", name = "파일럿 연구"),
    "sampling" = list(icon = "📊", name = "표본 분석"),
    "full" = list(icon = "🌍", name = "전체 분석"),
    list(icon = "❓", name = "알 수 없음")
  )
  
  cat(sprintf("%s %s 모드 결과:\n", mode_info$icon, mode_info$name))
  
  original_stats <- original_data %>%
    count(구분) %>%
    mutate(비율 = round(n / nrow(original_data) * 100, 1))
  
  # 전체 분석이 아닌 경우에만 샘플링 정보 표시
  if (mode != "full") {
    sampled_stats <- sampled_data %>%
      count(구분) %>%
      mutate(비율 = round(n / nrow(sampled_data) * 100, 1))
    
    cat("\n📋 원본 데이터:\n")
    for(i in 1:nrow(original_stats)) {
      cat(sprintf("   %s: %d개 (%.1f%%)\n", 
                  original_stats$구분[i], original_stats$n[i], original_stats$비율[i]))
    }
    
    cat(sprintf("\n%s 선택된 데이터:\n", mode_info$icon))
    for(i in 1:nrow(sampled_stats)) {
      cat(sprintf("   %s: %d개 (%.1f%%)\n", 
                  sampled_stats$구분[i], sampled_stats$n[i], sampled_stats$비율[i]))
    }
    
    # 게시글 수 정보
    original_posts <- original_data %>% filter(구분 == "게시글") %>% nrow()
    sampled_posts <- sampled_data %>% filter(구분 == "게시글") %>% nrow()
    
    cat(sprintf("\n📝 게시글 정보:\n"))
    cat(sprintf("   원본: %d개 → 선택: %d개 (%.1f%%)\n", 
                original_posts, sampled_posts, 
                round(sampled_posts/original_posts*100, 1)))
    
    sampling_ratio <- round(nrow(sampled_data)/nrow(original_data)*100, 1)
    cat(sprintf("\n📊 전체 선택 비율: %.1f%% (%d/%d)\n", 
                sampling_ratio, nrow(sampled_data), nrow(original_data)))
    
    # 모드별 추가 정보
    if (mode == "code_check") {
      cat("\n💡 코드 점검 완료 후 다음 단계:\n")
      cat("   1. 결과 검토 및 프롬프트 조정\n")
      cat("   2. 파일럿 연구 실행 고려\n")
    } else if (mode == "pilot") {
      cat("\n💡 파일럿 연구 완료 후 다음 단계:\n")
      cat("   1. 예비 결과 분석\n")
      cat("   2. 방법론 최종 검증\n")
      cat("   3. 표본 분석 실행 고려\n")
    } else if (mode == "sampling") {
      cat("\n💡 표본 분석 - 인간 코딩 검증 권장\n")
    }
    
  } else {
    cat("\n📊 전체 분석 모드:\n")
    for(i in 1:nrow(original_stats)) {
      cat(sprintf("   %s: %d개 (%.1f%%)\n", 
                  original_stats$구분[i], original_stats$n[i], original_stats$비율[i]))
    }
    cat(sprintf("\n총 분석 대상: %d개\n", nrow(original_data)))
    cat("\n💡 전체 분석 - 표본 기반 인간 코딩 검증 권장\n")
  }
  
  cat(rep("=", 60), "\n\n")
}