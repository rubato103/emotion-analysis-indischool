# 재분석 시스템 사용 예제 및 실습 가이드
# 프롬프트 개선 및 품질 문제로 인한 재분석 시나리오

source("reanalysis_manager.R")
source("recovery_system.R")

# =============================================================================
# 시나리오 1: 샘플링 테스트 결과가 좋지 않은 경우
# =============================================================================

cat("=== 시나리오 1: 낮은 품질의 샘플 테스트 결과 처리 ===\n")

# 재분석 관리자 초기화
reanalysis_mgr <- ReanalysisManager$new()

# 1-1. 샘플 테스트 결과 품질 평가
sample_results_file <- "results/analysis_results_SAMPLE_100.RDS"
if (file.exists(sample_results_file)) {
  sample_results <- readRDS(sample_results_file)
  
  # 품질 평가 실행
  quality_eval <- reanalysis_mgr$evaluate_analysis_quality(
    sample_results, 
    prompt_version_id = "current_sample_test"
  )
  
  cat(sprintf("샘플 테스트 품질 점수: %.2f\n", quality_eval$quality_score))
  cat("발견된 문제점:\n")
  if (is.character(quality_eval$issues)) {
    for (issue in quality_eval$issues) {
      cat(sprintf("  - %s\n", issue))
    }
  }
  
  # 재분석 필요한 경우
  if (quality_eval$needs_reanalysis) {
    cat("\n🔄 재분석이 필요합니다!\n")
    
    # 현재 프롬프트 버전 등록 (개선 전)
    current_prompt_version <- reanalysis_mgr$register_prompt_version(
      analyze_emotion_robust,  # 현재 분석 함수
      description = "초기 프롬프트 버전 - 품질 문제로 개선 필요",
      performance_data = list(quality_score = quality_eval$quality_score)
    )
    
    # 문제가 있는 분석 이력 무효화
    reanalysis_mgr$invalidate_analysis_history(
      invalidation_criteria = list(
        analysis_types = c("sample", "test"),
        quality_threshold = 0.6,
        date_range = c(Sys.time() - (7*24*60*60), Sys.time())
      ),
      reason = "낮은 품질로 인한 프롬프트 개선 후 재분석"
    )
    
    cat("✅ 품질이 낮은 분석 이력을 무효화했습니다.\n")
  }
} else {
  cat("샘플 테스트 결과 파일이 없습니다. 먼저 02_단건분석_테스트_v2.R을 실행하세요.\n")
}

# =============================================================================
# 시나리오 2: 프롬프트 개선 후 재분석 실행
# =============================================================================

cat("\n=== 시나리오 2: 프롬프트 개선 후 재분석 ===\n")

# 2-1. 개선된 프롬프트 함수 (예시)
analyze_emotion_improved <- function(prompt_text, model_to_use = "gemini-2.5-flash", 
                                   temp_to_use = 0.1, top_p_to_use = 0.9) {
  # 개선된 프롬프트 - 더 명확한 지시사항과 예시 포함
  improved_prompt <- paste0(
    "다음 텍스트의 감정을 매우 정확하게 분석해주세요. ",
    "감정 점수는 0.0-1.0 범위로 정확히 제공하고, ",
    "불확실한 경우 보수적으로 판단하세요.\n\n",
    "분석할 텍스트: ", prompt_text,
    "\n\n응답 형식을 정확히 지켜주세요..."
  )
  
  # 실제 API 호출은 기존 함수와 동일하지만 개선된 프롬프트 사용
  return(analyze_emotion_robust(improved_prompt, model_to_use, temp_to_use, top_p_to_use))
}

# 2-2. 개선된 프롬프트 버전 등록
improved_version_id <- reanalysis_mgr$register_prompt_version(
  analyze_emotion_improved,
  description = "개선된 프롬프트 v2 - 더 명확한 지시사항과 엄격한 품질 기준",
  performance_data = list(expected_improvement = "오류율 50% 감소, 중립 과다 분류 개선")
)

cat(sprintf("새 프롬프트 버전 등록: %s\n", improved_version_id))

# 2-3. 재분석 대상 식별
reanalysis_candidates <- reanalysis_mgr$identify_reanalysis_candidates(
  criteria = list(
    older_than_days = 7,
    error_types = c("API 오류", "파싱 오류"),
    low_quality_versions = c("current_sample_test")  # 이전 버전의 결과들
  )
)

if (nrow(reanalysis_candidates) > 0) {
  cat(sprintf("재분석 대상: %d건 식별\n", nrow(reanalysis_candidates)))
  
  # 2-4. 재분석 계획 수립
  reanalysis_plan <- reanalysis_mgr$create_reanalysis_plan(
    target_data = reanalysis_candidates,
    reason = "프롬프트 개선으로 인한 품질 향상 재분석",
    priority_scoring = TRUE
  )
  
  cat(sprintf("재분석 계획:\n"))
  cat(sprintf("  - 총 %d건 재분석\n", reanalysis_plan$total_items))
  cat(sprintf("  - %d개 배치로 나누어 실행\n", reanalysis_plan$num_batches))
  cat(sprintf("  - 예상 소요 시간: %.1f분\n", reanalysis_plan$total_estimated_time_mins))
  cat(sprintf("  - 예상 비용: $%.3f\n", reanalysis_plan$estimated_api_cost))
  
  # 사용자 확인 후 실행 여부 결정 (실제 환경에서는 사용자 입력)
  proceed_with_reanalysis <- TRUE  # 예시에서는 자동으로 진행
  
  if (proceed_with_reanalysis) {
    cat("\n🚀 재분석 실행 시작...\n")
    
    # 체크포인트 관리자 초기화
    checkpoint_mgr <- CheckpointManager$new()
    
    # 배치별로 재분석 실행
    for (i in seq_along(reanalysis_plan$batches)) {
      batch <- reanalysis_plan$batches[[i]]
      cat(sprintf("배치 %d/%d 처리 중... (%d건)\n", i, length(reanalysis_plan$batches), batch$size))
      
      # 체크포인트 저장
      checkpoint_mgr$save_checkpoint(
        batch$data, 
        step_name = sprintf("reanalysis_batch_%d", i),
        metadata = list(
          batch_id = i, 
          prompt_version = improved_version_id,
          reason = reanalysis_plan$reason
        )
      )
      
      # 실제 재분석 실행 (예시 - 실제로는 개선된 함수 사용)
      # batch_results <- batch$data %>%
      #   rowwise() %>%
      #   mutate(reanalysis_result = list(analyze_emotion_improved(prompt)))
      
      cat(sprintf("  ✅ 배치 %d 완료\n", i))
    }
    
    cat("✅ 모든 재분석 완료!\n")
  }
} else {
  cat("재분석할 대상이 없습니다.\n")
}

# =============================================================================
# 시나리오 3: 분석 품질 비교 및 개선 효과 측정
# =============================================================================

cat("\n=== 시나리오 3: 품질 개선 효과 측정 ===\n")

# 3-1. 개선 전후 비교 함수
compare_analysis_quality <- function(before_results, after_results, version_before, version_after) {
  before_eval <- reanalysis_mgr$evaluate_analysis_quality(before_results, version_before)
  after_eval <- reanalysis_mgr$evaluate_analysis_quality(after_results, version_after)
  
  improvement <- list(
    quality_score_change = after_eval$quality_score - before_eval$quality_score,
    error_rate_improvement = before_eval$metrics$error_rate - after_eval$metrics$error_rate,
    valid_rate_improvement = after_eval$metrics$valid_rate - before_eval$metrics$valid_rate,
    emotion_diversity_change = after_eval$metrics$emotion_diversity - before_eval$metrics$emotion_diversity,
    
    before_issues = before_eval$issues,
    after_issues = after_eval$issues,
    
    summary = sprintf(
      "품질 점수: %.2f → %.2f (%.2f 개선)\n오류율: %.1f%% → %.1f%% (%.1f%% 개선)\n유효율: %.1f%% → %.1f%% (%.1f%% 개선)",
      before_eval$quality_score, after_eval$quality_score, after_eval$quality_score - before_eval$quality_score,
      before_eval$metrics$error_rate * 100, after_eval$metrics$error_rate * 100, (before_eval$metrics$error_rate - after_eval$metrics$error_rate) * 100,
      before_eval$metrics$valid_rate * 100, after_eval$metrics$valid_rate * 100, (after_eval$metrics$valid_rate - before_eval$metrics$valid_rate) * 100
    )
  )
  
  return(improvement)
}

# 예시 비교 (실제 데이터가 있는 경우)
if (exists("sample_results") && nrow(sample_results) > 0) {
  # 가상의 개선된 결과 생성 (실제로는 재분석 결과 사용)
  improved_sample_results <- sample_results %>%
    mutate(
      # 예시: 개선된 결과는 오류율이 낮고 감정 분포가 더 다양함
      dominant_emotion = case_when(
        dominant_emotion %in% c("API 오류", "파싱 오류") ~ sample(c("기쁨", "슬픔", "분노", "중립"), 1),
        dominant_emotion == "중립" & runif(n()) > 0.7 ~ sample(c("기쁨", "슬픔", "분노"), 1),
        TRUE ~ dominant_emotion
      )
    )
  
  quality_comparison <- compare_analysis_quality(
    sample_results, improved_sample_results,
    "current_sample_test", improved_version_id
  )
  
  cat("품질 개선 효과:\n")
  cat(quality_comparison$summary)
  cat("\n")
}

# =============================================================================
# 시나리오 4: 자동 재분석 권장 시스템
# =============================================================================

cat("\n=== 시나리오 4: 자동 재분석 권장 ===\n")

# 4-1. 시스템 전체 분석 상태 체크
recommendations <- reanalysis_mgr$recommend_reanalysis(
  recent_results = if(exists("sample_results")) sample_results else NULL,
  auto_check_history = TRUE
)

if (length(recommendations) > 0) {
  cat("🔍 재분석 권장사항:\n")
  for (rec_type in names(recommendations)) {
    rec <- recommendations[[rec_type]]
    cat(sprintf("\n[%s 우선순위] %s\n", rec$priority, rec$reason))
    cat(sprintf("  영향 범위: %d건\n", rec$affected_count))
    if (!is.null(rec$suggestion)) {
      cat(sprintf("  권장사항: %s\n", rec$suggestion))
    }
    if (!is.null(rec$issues)) {
      cat("  문제점:\n")
      for (issue in rec$issues) {
        cat(sprintf("    - %s\n", issue))
      }
    }
  }
} else {
  cat("✅ 현재 재분석이 필요한 항목이 없습니다.\n")
}

# =============================================================================
# 보너스: 재분석 결과 병합 및 최종 검증
# =============================================================================

cat("\n=== 최종: 재분석 결과 통합 및 검증 ===\n")

merge_reanalysis_results <- function(original_results, reanalysis_results, conflict_resolution = "keep_latest") {
  # 재분석된 항목과 기존 결과 병합
  if (conflict_resolution == "keep_latest") {
    # 재분석 결과를 우선하여 병합
    merged <- bind_rows(
      original_results %>% anti_join(reanalysis_results, by = c("post_id", "comment_id")),
      reanalysis_results
    ) %>%
    arrange(post_id, comment_id)
  }
  
  return(merged)
}

cat("재분석 시스템 설정 완료!\n")
cat("\n사용 방법:\n")
cat("1. 샘플 테스트 후 reanalysis_mgr$evaluate_analysis_quality() 실행\n")
cat("2. 품질이 낮은 경우 invalidate_analysis_history() 후 프롬프트 개선\n")
cat("3. identify_reanalysis_candidates()로 대상 식별 후 재분석 실행\n")
cat("4. compare_analysis_quality()로 개선 효과 측정\n")
cat("5. recommend_reanalysis()로 시스템 전체 상태 모니터링\n")

# 분석 이력 정리
reanalysis_mgr$tracker$cleanup_old_history(90)

cat("\n=== 재분석 시스템 예제 완료 ===\n")