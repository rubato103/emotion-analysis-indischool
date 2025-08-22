# 분석 결과 추적 및 중복 방지 시스템

# 분석 이력 관리 클래스
AnalysisTracker <- R6::R6Class("AnalysisTracker",
  public = list(
    history_file = NULL,
    history_dir = "analysis_history",
    
    initialize = function() {
      if (!dir.exists(self$history_dir)) {
        dir.create(self$history_dir, recursive = TRUE)
      }
      self$history_file <- file.path(self$history_dir, "analysis_history.RDS")
      
      # 기존 이력 파일이 없으면 빈 데이터프레임 생성
      if (!file.exists(self$history_file)) {
        empty_history <- data.frame(
          id = character(),
          post_id = numeric(),
          comment_id = numeric(),
          analysis_date = as.POSIXct(character()),
          analysis_type = character(),  # "sample", "full", "test"
          model_used = character(),
          dominant_emotion = character(),
          analysis_file = character(),
          stringsAsFactors = FALSE
        )
        saveRDS(empty_history, self$history_file)
        log_message("INFO", "새 분석 이력 파일 생성")
      }
    },
    
    # 분석 이력 로드
    load_history = function() {
      if (file.exists(self$history_file)) {
        return(readRDS(self$history_file))
      }
      return(data.frame())
    },
    
    # 분석 결과 등록
    register_analysis = function(analysis_results, analysis_type = "sample", model_used = NULL, analysis_file = NULL) {
      history <- self$load_history()
      
      # 새로운 분석 결과 준비
      new_entries <- analysis_results %>%
        select(any_of(c("post_id", "comment_id", "dominant_emotion"))) %>%
        mutate(
          id = paste0(post_id, "_", ifelse(is.na(comment_id), 0, comment_id)),
          analysis_date = Sys.time(),
          analysis_type = analysis_type,
          model_used = model_used %||% "unknown",
          analysis_file = analysis_file %||% "unknown"
        ) %>%
        select(id, post_id, comment_id, analysis_date, analysis_type, model_used, dominant_emotion, analysis_file)
      
      # 기존 이력과 병합 (중복 제거)
      updated_history <- bind_rows(history, new_entries) %>%
        group_by(id) %>%
        slice_max(analysis_date, n = 1, with_ties = FALSE) %>%  # 가장 최근 분석만 유지
        ungroup()
      
      # 이력 파일 저장
      saveRDS(updated_history, self$history_file)
      
      log_message("INFO", sprintf("분석 이력 등록: %d건 (%s)", nrow(new_entries), analysis_type))
      return(invisible(updated_history))
    },
    
    # 기분석 데이터 식별
    get_analyzed_ids = function(analysis_type = NULL, model_filter = NULL, days_back = NULL) {
      history <- self$load_history()
      
      if (nrow(history) == 0) {
        return(character())
      }
      
      # 필터링 조건 적용
      filtered_history <- history
      
      if (!is.null(analysis_type)) {
        filtered_history <- filtered_history %>%
          filter(analysis_type %in% !!analysis_type)
      }
      
      if (!is.null(model_filter)) {
        filtered_history <- filtered_history %>%
          filter(model_used == !!model_filter)
      }
      
      if (!is.null(days_back)) {
        cutoff_date <- Sys.time() - (days_back * 24 * 60 * 60)
        filtered_history <- filtered_history %>%
          filter(analysis_date >= !!cutoff_date)
      }
      
      return(unique(filtered_history$id))
    },
    
    # 미분석 데이터 필터링
    filter_unanalyzed = function(data, exclude_types = c("sample", "test"), 
                                model_filter = NULL, days_back = 30) {
      
      # 데이터에 고유 ID 생성
      data_with_id <- data %>%
        mutate(
          id = paste0(post_id, "_", ifelse(is.na(comment_id), 0, comment_id))
        )
      
      # 기분석 ID 목록 가져오기
      analyzed_ids <- self$get_analyzed_ids(
        analysis_type = exclude_types,
        model_filter = model_filter,
        days_back = days_back
      )
      
      if (length(analyzed_ids) == 0) {
        log_message("INFO", "기분석 데이터가 없습니다. 전체 데이터를 분석합니다.")
        return(data_with_id %>% select(-id))
      }
      
      # 미분석 데이터만 필터링
      unanalyzed_data <- data_with_id %>%
        filter(!id %in% analyzed_ids) %>%
        select(-id)
      
      analyzed_count <- nrow(data) - nrow(unanalyzed_data)
      
      log_message("INFO", sprintf("중복 분석 제외: 전체 %d건 중 %d건은 기분석, %d건만 새로 분석", 
                                 nrow(data), analyzed_count, nrow(unanalyzed_data)))
      
      return(unanalyzed_data)
    },
    
    # 분석 통계 확인
    get_analysis_stats = function() {
      history <- self$load_history()
      
      if (nrow(history) == 0) {
        return(list(total = 0, by_type = data.frame()))
      }
      
      stats <- list(
        total = nrow(history),
        by_type = history %>%
          group_by(analysis_type) %>%
          summarise(
            count = n(),
            latest_analysis = max(analysis_date),
            .groups = "drop"
          ),
        by_model = history %>%
          group_by(model_used) %>%
          summarise(
            count = n(),
            latest_analysis = max(analysis_date),
            .groups = "drop"
          ),
        recent_activity = history %>%
          filter(analysis_date >= Sys.time() - (7 * 24 * 60 * 60)) %>%
          nrow()
      )
      
      return(stats)
    },
    
    # 분석 이력 정리
    cleanup_old_history = function(keep_days = 90) {
      history <- self$load_history()
      
      if (nrow(history) == 0) return(invisible(NULL))
      
      cutoff_date <- Sys.time() - (keep_days * 24 * 60 * 60)
      
      # 각 ID별로 최신 기록은 유지하되, 오래된 중복 기록만 삭제
      cleaned_history <- history %>%
        group_by(id) %>%
        filter(analysis_date == max(analysis_date) | analysis_date >= cutoff_date) %>%
        ungroup()
      
      removed_count <- nrow(history) - nrow(cleaned_history)
      
      if (removed_count > 0) {
        saveRDS(cleaned_history, self$history_file)
        log_message("INFO", sprintf("%d개의 오래된 분석 이력을 정리했습니다.", removed_count))
      }
      
      return(invisible(cleaned_history))
    }
  )
)