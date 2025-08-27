# 재분석 관리 시스템
# 프롬프트 개선 및 품질 문제로 인한 재분석 지원

# 프롬프트 버전 관리 및 재분석 클래스
ReanalysisManager <- R6::R6Class("ReanalysisManager",
  public = list(
    tracker = NULL,
    prompt_versions_file = "analysis_history/prompt_versions.RDS",
    quality_thresholds = NULL,
    
    initialize = function() {
      self$tracker <- AnalysisTracker$new()
      
      # 품질 임계값 설정
      self$quality_thresholds <- list(
        min_valid_emotions = 0.7,      # 유효한 감정 결과 비율
        max_error_rate = 0.1,          # 최대 오류율  
        min_confidence_score = 0.6,    # 최소 신뢰도 점수
        max_parsing_errors = 0.05      # 최대 파싱 오류율
      )
      
      # 프롬프트 버전 파일 초기화
      if (!file.exists(self$prompt_versions_file)) {
        empty_versions <- data.frame(
          version_id = character(),
          prompt_hash = character(),
          creation_date = as.POSIXct(character()),
          description = character(),
          prompt_content = character(),
          performance_metrics = character(),
          is_active = logical(),
          stringsAsFactors = FALSE
        )
        saveRDS(empty_versions, self$prompt_versions_file)
      }
    },
    
    # 현재 프롬프트 버전 등록
    register_prompt_version = function(prompt_function, description = "", performance_data = NULL) {
      # 프롬프트 함수의 해시값 계산
      prompt_code <- deparse(prompt_function)
      prompt_hash <- digest::digest(prompt_code, algo = "md5")
      
      versions <- readRDS(self$prompt_versions_file)
      
      # 기존 버전과 동일한지 확인
      if (prompt_hash %in% versions$prompt_hash) {
        existing_version <- versions[versions$prompt_hash == prompt_hash, ]
        log_message("INFO", sprintf("기존 프롬프트 버전 사용: %s", existing_version$version_id[1]))
        return(existing_version$version_id[1])
      }
      
      # 새 버전 생성
      new_version_id <- sprintf("v%s_%s", format(Sys.Date(), "%Y%m%d"), 
                               substr(prompt_hash, 1, 8))
      
      new_version <- data.frame(
        version_id = new_version_id,
        prompt_hash = prompt_hash,
        creation_date = Sys.time(),
        description = description,
        prompt_content = paste(prompt_code, collapse = "\n"),
        performance_metrics = ifelse(is.null(performance_data), 
                                   NA_character_, 
                                   jsonlite::toJSON(performance_data)),
        is_active = TRUE,
        stringsAsFactors = FALSE
      )
      
      # 기존 버전들을 비활성화
      versions$is_active <- FALSE
      updated_versions <- rbind(versions, new_version)
      
      saveRDS(updated_versions, self$prompt_versions_file)
      log_message("INFO", sprintf("새 프롬프트 버전 등록: %s", new_version_id))
      
      return(new_version_id)
    },
    
    # 분석 품질 평가
    evaluate_analysis_quality = function(analysis_results, prompt_version_id = NULL) {
      if (nrow(analysis_results) == 0) {
        return(list(quality_score = 0, issues = "분석 결과가 없습니다.", needs_reanalysis = TRUE))
      }
      
      # 품질 지표 계산
      metrics <- list(
        total_count = nrow(analysis_results),
        error_count = sum(analysis_results$combinated_emotion %in% c("API 오류", "파싱 오류", "분석 오류"), na.rm = TRUE),
        na_count = sum(is.na(analysis_results$combinated_emotion)),
        valid_count = sum(!is.na(analysis_results$combinated_emotion) & 
                         !analysis_results$combinated_emotion %in% c("API 오류", "파싱 오류", "분석 오류")),
        
        # 감정 분포 분석
        neutral_heavy = sum(analysis_results$combinated_emotion == "중립", na.rm = TRUE),
        emotion_diversity = length(unique(analysis_results$combinated_emotion[!is.na(analysis_results$combinated_emotion)])),
        
        # 신뢰도 관련 (rationale 길이로 추정)
        avg_rationale_length = mean(nchar(analysis_results$rationale), na.rm = TRUE),
        
        # PAD 점수 유효성
        valid_pad_scores = sum(!is.na(analysis_results$P) & !is.na(analysis_results$A) & !is.na(analysis_results$D))
      )
      
      # 비율 계산
      metrics$error_rate <- metrics$error_count / metrics$total_count
      metrics$valid_rate <- metrics$valid_count / metrics$total_count
      metrics$neutral_rate <- metrics$neutral_heavy / metrics$total_count
      metrics$parsing_success_rate <- 1 - (metrics$na_count / metrics$total_count)
      
      # 품질 점수 계산 (0-1 스케일)
      quality_score <- (
        (metrics$valid_rate * 0.4) +                    # 유효 결과 비율 (40%)
        ((1 - metrics$error_rate) * 0.3) +              # 오류율 반전 (30%)
        (min(metrics$emotion_diversity / 8, 1) * 0.2) + # 감정 다양성 (20%)
        (metrics$parsing_success_rate * 0.1)            # 파싱 성공률 (10%)
      )
      
      # 문제점 식별
      issues <- c()
      needs_reanalysis <- FALSE
      
      if (metrics$error_rate > self$quality_thresholds$max_error_rate) {
        issues <- c(issues, sprintf("높은 오류율: %.1f%% (임계값: %.1f%%)", 
                                   metrics$error_rate * 100, 
                                   self$quality_thresholds$max_error_rate * 100))
        needs_reanalysis <- TRUE
      }
      
      if (metrics$valid_rate < self$quality_thresholds$min_valid_emotions) {
        issues <- c(issues, sprintf("낮은 유효 결과율: %.1f%% (임계값: %.1f%%)", 
                                   metrics$valid_rate * 100, 
                                   self$quality_thresholds$min_valid_emotions * 100))
        needs_reanalysis <- TRUE
      }
      
      if (metrics$neutral_rate > 0.7) {
        issues <- c(issues, sprintf("과도한 중립 감정: %.1f%% (감정 구분력 부족 의심)", 
                                   metrics$neutral_rate * 100))
        needs_reanalysis <- TRUE
      }
      
      if (metrics$emotion_diversity < 5) {
        issues <- c(issues, sprintf("감정 다양성 부족: %d종류 (8종류 중)", 
                                   metrics$emotion_diversity))
      }
      
      if (quality_score < self$quality_thresholds$min_confidence_score) {
        needs_reanalysis <- TRUE
      }
      
      # 결과 정리
      evaluation <- list(
        quality_score = quality_score,
        metrics = metrics,
        issues = if (length(issues) > 0) issues else "품질 문제 없음",
        needs_reanalysis = needs_reanalysis,
        prompt_version_id = prompt_version_id,
        evaluation_date = Sys.time()
      )
      
      return(evaluation)
    },
    
    # 재분석 필요 데이터 식별
    identify_reanalysis_candidates = function(criteria = list()) {
      history <- self$tracker$load_history()
      
      if (nrow(history) == 0) {
        return(data.frame())
      }
      
      # 기본 재분석 후보 조건
      default_criteria <- list(
        older_than_days = 7,                    # 7일 이상 된 분석
        error_types = c("API 오류", "파싱 오류"), # 오류 결과
        low_quality_versions = c(),             # 품질이 낮은 프롬프트 버전
        specific_analysis_types = c(),          # 특정 분석 유형
        prompt_versions_to_update = c()         # 특정 프롬프트 버전
      )
      
      # 사용자 기준과 기본 기준 병합
      criteria <- modifyList(default_criteria, criteria)
      
      candidates <- history
      
      # 날짜 기준 필터링
      if (!is.null(criteria$older_than_days)) {
        cutoff_date <- Sys.time() - (criteria$older_than_days * 24 * 60 * 60)
        candidates <- candidates %>% filter(analysis_date < cutoff_date)
      }
      
      # 오류 유형 기준
      if (length(criteria$error_types) > 0) {
        candidates <- candidates %>% 
          filter(combinated_emotion %in% criteria$error_types)
      }
      
      # 특정 프롬프트 버전
      if (length(criteria$prompt_versions_to_update) > 0) {
        # 실제 구현에서는 prompt_version_id 컬럼이 있다고 가정
        candidates <- candidates %>% 
          filter(get("prompt_version_id", .) %in% criteria$prompt_versions_to_update)
      }
      
      return(candidates)
    },
    
    # 선택적 이력 무효화
    invalidate_analysis_history = function(invalidation_criteria, reason = "") {
      history <- self$tracker$load_history()
      
      if (nrow(history) == 0) {
        log_message("WARN", "무효화할 이력이 없습니다.")
        return(history)
      }
      
      # 무효화 대상 식별
      to_invalidate <- history
      
      if (!is.null(invalidation_criteria$analysis_types)) {
        to_invalidate <- to_invalidate %>%
          filter(analysis_type %in% invalidation_criteria$analysis_types)
      }
      
      if (!is.null(invalidation_criteria$date_range)) {
        to_invalidate <- to_invalidate %>%
          filter(analysis_date >= invalidation_criteria$date_range[1] &
                 analysis_date <= invalidation_criteria$date_range[2])
      }
      
      if (!is.null(invalidation_criteria$model_filter)) {
        to_invalidate <- to_invalidate %>%
          filter(model_used == invalidation_criteria$model_filter)
      }
      
      if (!is.null(invalidation_criteria$quality_threshold)) {
        # 품질 기준으로 필터링 (실제 구현에서는 품질 점수 컬럼 필요)
        to_invalidate <- to_invalidate %>%
          filter(get("quality_score", .) < invalidation_criteria$quality_threshold)
      }
      
      if (!is.null(invalidation_criteria$specific_ids)) {
        to_invalidate <- to_invalidate %>%
          filter(id %in% invalidation_criteria$specific_ids)
      }
      
      # 백업 생성
      backup_file <- sprintf("analysis_history/backup_before_invalidation_%s.RDS", 
                            format(Sys.time(), "%Y%m%d_%H%M%S"))
      saveRDS(history, backup_file)
      
      # 무효화 실행 (해당 레코드 삭제)
      remaining_history <- history %>%
        anti_join(to_invalidate, by = "id")
      
      # 무효화 로그 추가
      invalidation_log <- data.frame(
        invalidation_date = Sys.time(),
        reason = reason,
        invalidated_count = nrow(to_invalidate),
        criteria = jsonlite::toJSON(invalidation_criteria),
        backup_file = backup_file,
        stringsAsFactors = FALSE
      )
      
      # 무효화 이력 저장
      invalidation_log_file <- "analysis_history/invalidation_log.RDS"
      if (file.exists(invalidation_log_file)) {
        existing_log <- readRDS(invalidation_log_file)
        updated_log <- rbind(existing_log, invalidation_log)
      } else {
        updated_log <- invalidation_log
      }
      saveRDS(updated_log, invalidation_log_file)
      
      # 업데이트된 이력 저장
      saveRDS(remaining_history, self$tracker$history_file)
      
      log_message("INFO", sprintf("%d건의 분석 이력을 무효화했습니다. 이유: %s", 
                                 nrow(to_invalidate), reason))
      log_message("INFO", sprintf("백업 파일: %s", backup_file))
      
      return(remaining_history)
    },
    
    # 품질 기반 자동 재분석 권장
    recommend_reanalysis = function(recent_results = NULL, auto_check_history = TRUE) {
      recommendations <- list()
      
      # 최근 결과 품질 평가
      if (!is.null(recent_results)) {
        quality_eval <- self$evaluate_analysis_quality(recent_results)
        
        if (quality_eval$needs_reanalysis) {
          recommendations$recent_analysis <- list(
            priority = "HIGH",
            reason = "최근 분석 결과 품질 저하",
            issues = quality_eval$issues,
            quality_score = quality_eval$quality_score,
            affected_count = nrow(recent_results)
          )
        }
      }
      
      # 이력 기반 자동 체크
      if (auto_check_history) {
        # 오류율이 높은 이전 분석 식별
        error_candidates <- self$identify_reanalysis_candidates(list(
          error_types = c("API 오류", "파싱 오류", "분석 오류"),
          older_than_days = 3
        ))
        
        if (nrow(error_candidates) > 0) {
          recommendations$error_recovery <- list(
            priority = "MEDIUM",
            reason = "이전 분석의 높은 오류율",
            affected_count = nrow(error_candidates),
            suggestion = "네트워크 안정화 후 재분석 권장"
          )
        }
        
        # 오래된 저품질 분석 식별
        old_analyses <- self$identify_reanalysis_candidates(list(
          older_than_days = 30
        ))
        
        if (nrow(old_analyses) > 100) {  # 상당한 양의 오래된 분석
          recommendations$version_update <- list(
            priority = "LOW",
            reason = "프롬프트 개선을 위한 대량 재분석 고려",
            affected_count = nrow(old_analyses),
            suggestion = "프롬프트 최적화 후 선택적 재분석"
          )
        }
      }
      
      return(recommendations)
    },
    
    # 재분석 실행 계획 수립
    create_reanalysis_plan = function(target_data, reason = "", priority_scoring = TRUE) {
      if (nrow(target_data) == 0) {
        return(list(batches = list(), total_cost = 0, estimated_time = 0))
      }
      
      # 우선순위 점수 계산 (선택사항)
      if (priority_scoring) {
        target_data <- target_data %>%
          mutate(
            priority_score = case_when(
              combinated_emotion %in% c("API 오류", "파싱 오류") ~ 10,  # 오류 최우선
              combinated_emotion == "분석 오류" ~ 8,
              combinated_emotion == "중립" ~ 6,                         # 중립 재검토
              is.na(combinated_emotion) ~ 9,                           # NA 결과 우선
              TRUE ~ 5
            )
          ) %>%
          arrange(desc(priority_score), desc(analysis_date))
      }
      
      # 배치 계획 수립
      batch_size <- RECOVERY_CONFIG$batch_size
      num_batches <- ceiling(nrow(target_data) / batch_size)
      
      batches <- list()
      for (i in 1:num_batches) {
        start_idx <- (i - 1) * batch_size + 1
        end_idx <- min(i * batch_size, nrow(target_data))
        
        batch_data <- target_data[start_idx:end_idx, ]
        
        batches[[i]] <- list(
          batch_id = i,
          data = batch_data,
          size = nrow(batch_data),
          estimated_time_mins = nrow(batch_data) / API_CONFIG$rate_limit_per_minute * 60,
          priority = if (priority_scoring) mean(batch_data$priority_score) else 5
        )
      }
      
      plan <- list(
        reason = reason,
        total_items = nrow(target_data),
        num_batches = num_batches,
        batches = batches,
        total_estimated_time_mins = sum(sapply(batches, function(b) b$estimated_time_mins)),
        estimated_api_cost = nrow(target_data) * 0.001,  # 가정: API 호출당 $0.001
        creation_date = Sys.time()
      )
      
      return(plan)
    },
    
    # 재분석 실행 (체크포인트 기반)
    execute_reanalysis_plan = function(plan, analysis_function = NULL, checkpoint_interval = 5) {
      if (is.null(analysis_function)) {
        stop("분석 함수가 제공되지 않았습니다.")
      }
      
      log_message("INFO", sprintf("재분석 실행 시작: %s", plan$reason))
      log_message("INFO", sprintf("총 %d건, %d개 배치, 예상 시간 %.1f분", 
                                 plan$total_items, plan$num_batches, plan$total_estimated_time_mins))
      
      # 체크포인트 관리자 초기화
      checkpoint_mgr <- CheckpointManager$new()
      
      # 실행 결과 저장
      completed_batches <- list()
      failed_batches <- list()
      
      for (i in seq_along(plan$batches)) {
        batch <- plan$batches[[i]]
        
        tryCatch({
          log_message("INFO", sprintf("배치 %d/%d 처리 중... (%d건)", 
                                     i, length(plan$batches), batch$size))
          
          # 체크포인트 저장 (일정 간격마다)
          if (i %% checkpoint_interval == 0 || i == 1) {
            checkpoint_mgr$save_checkpoint(
              data = list(
                completed_batches = completed_batches,
                current_batch = i,
                plan = plan
              ),
              step_name = sprintf("reanalysis_progress_%s", format(Sys.time(), "%Y%m%d_%H%M%S")),
              metadata = list(
                total_batches = length(plan$batches),
                current_batch = i,
                reason = plan$reason
              )
            )
          }
          
          # 배치 분석 실행
          batch_results <- batch$data %>%
            rowwise() %>%
            do({
              result <- analysis_function(.$prompt)
              bind_cols(., result)
            }) %>%
            ungroup()
          
          # 성공한 배치 저장
          completed_batches[[i]] <- list(
            batch_id = i,
            results = batch_results,
            completion_time = Sys.time(),
            success_count = nrow(batch_results)
          )
          
          log_message("INFO", sprintf("배치 %d 완료 (%d건)", i, nrow(batch_results)))
          
          # API 레이트 제한 준수
          if (i < length(plan$batches)) {
            Sys.sleep(API_CONFIG$wait_time_seconds)
          }
          
        }, error = function(e) {
          log_message("ERROR", sprintf("배치 %d 실패: %s", i, e$message))
          failed_batches[[i]] <- list(
            batch_id = i,
            error = e$message,
            failure_time = Sys.time()
          )
        })
      }
      
      # 실행 결과 정리
      execution_summary <- list(
        plan = plan,
        completed_count = length(completed_batches),
        failed_count = length(failed_batches),
        total_items_processed = sum(sapply(completed_batches, function(b) b$success_count)),
        execution_start = plan$creation_date,
        execution_end = Sys.time(),
        completed_batches = completed_batches,
        failed_batches = failed_batches
      )
      
      # 최종 체크포인트 저장
      checkpoint_mgr$save_checkpoint(
        execution_summary,
        step_name = "reanalysis_completed",
        metadata = list(
          success_rate = length(completed_batches) / length(plan$batches),
          total_processed = execution_summary$total_items_processed
        )
      )
      
      log_message("INFO", sprintf("재분석 완료: %d/%d 배치 성공, 총 %d건 처리", 
                                 length(completed_batches), length(plan$batches),
                                 execution_summary$total_items_processed))
      
      return(execution_summary)
    },
    
    # 품질 개선 효과 측정
    measure_improvement = function(before_results, after_results, before_version = NULL, after_version = NULL) {
      before_eval <- self$evaluate_analysis_quality(before_results, before_version)
      after_eval <- self$evaluate_analysis_quality(after_results, after_version)
      
      improvement <- list(
        quality_scores = list(
          before = before_eval$quality_score,
          after = after_eval$quality_score,
          improvement = after_eval$quality_score - before_eval$quality_score
        ),
        metrics_comparison = list(
          error_rate = list(
            before = before_eval$metrics$error_rate,
            after = after_eval$metrics$error_rate,
            improvement = before_eval$metrics$error_rate - after_eval$metrics$error_rate
          ),
          valid_rate = list(
            before = before_eval$metrics$valid_rate,
            after = after_eval$metrics$valid_rate,
            improvement = after_eval$metrics$valid_rate - before_eval$metrics$valid_rate
          ),
          emotion_diversity = list(
            before = before_eval$metrics$emotion_diversity,
            after = after_eval$metrics$emotion_diversity,
            improvement = after_eval$metrics$emotion_diversity - before_eval$metrics$emotion_diversity
          )
        ),
        issues_resolved = setdiff(before_eval$issues, after_eval$issues),
        new_issues = setdiff(after_eval$issues, before_eval$issues),
        overall_assessment = case_when(
          after_eval$quality_score - before_eval$quality_score >= 0.2 ~ "크게 개선됨",
          after_eval$quality_score - before_eval$quality_score >= 0.1 ~ "개선됨", 
          after_eval$quality_score - before_eval$quality_score >= 0.05 ~ "약간 개선됨",
          abs(after_eval$quality_score - before_eval$quality_score) < 0.05 ~ "변화 없음",
          TRUE ~ "품질 저하"
        ),
        cost_benefit = list(
          items_reanalyzed = nrow(after_results),
          estimated_cost = nrow(after_results) * 0.001,
          quality_gain = after_eval$quality_score - before_eval$quality_score,
          roi_estimate = ((after_eval$quality_score - before_eval$quality_score) * 100) / (nrow(after_results) * 0.001)
        ),
        recommendation = if (after_eval$quality_score - before_eval$quality_score >= 0.1) {
          "재분석 효과가 좋습니다. 유사한 데이터에 적용 권장"
        } else if (after_eval$quality_score - before_eval$quality_score >= 0.05) {
          "약간의 개선이 있습니다. 추가 최적화 고려"
        } else {
          "재분석 효과가 제한적입니다. 다른 개선 방법 검토 필요"
        }
      )
      
      return(improvement)
    }
  )
)