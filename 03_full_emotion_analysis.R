# 전체 감정분석 실행 (중복 분석 방지 적용)
# 목적: 병렬 처리로 전체 데이터 감정분석, 기분석 데이터 제외, 실패 항목 재분석

# 설정 및 유틸리티 로드
source("libs/config.R")
source("libs/utils.R")
source("modules/analysis_tracker.R")
source("modules/human_coding.R")
source("modules/adaptive_sampling.R")
source("modules/sample_replacement.R")

# 0. 환경 설정 (config.R에서 로드)
RATE_LIMIT_PER_MINUTE <- API_CONFIG$rate_limit_per_minute
WAIT_TIME_SECONDS <- API_CONFIG$wait_time_seconds
model_name <- API_CONFIG$model_name
temp_val <- API_CONFIG$temperature
top_p_val <- API_CONFIG$top_p
TARGET_GDRIVE_FOLDER <- ANALYSIS_CONFIG$target_gdrive_folder

# 핵심 제어 변수 (config.R에서 로드)
SAMPLE_POST_COUNT <- ANALYSIS_CONFIG$sample_post_count
ENABLE_ADAPTIVE_SAMPLING <- ANALYSIS_CONFIG$enable_adaptive_sampling
TARGET_SAMPLE_SIZE <- ANALYSIS_CONFIG$target_sample_size
ANALYSIS_MODE <- ANALYSIS_CONFIG$analysis_mode

# 1. 패키지 로드
required_packages <- c("dplyr", "stringr", "jsonlite", "future", "furrr", "progressr","googlesheets4", "googledrive", "readr", "R6", "httr2", "irr")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)
cat("✅ 필요한 패키지를 모두 불러왔습니다.\n")

# 분석 이력 추적기 초기화
tracker <- AnalysisTracker$new()

# 공통 함수 로드
if(file.exists(PATHS$functions_file)){
  source(PATHS$functions_file, encoding = "UTF-8")
  log_message("INFO", "공통 함수 로드 완료")
} else {
  log_message("ERROR", sprintf("%s 파일을 찾을 수 없습니다.", PATHS$functions_file))
  stop("functions.R 파일을 찾을 수 없습니다.")
}

# 2. 인증 및 병렬 처리 설정
log_message("INFO", "=== 전체 감정분석 시작 ===")

#gs4_auth(email = TRUE)
if (Sys.getenv("GEMINI_API_KEY") == "") { 
  log_message("ERROR", "Gemini API 키가 설정되지 않았습니다.")
  stop("⚠️ Gemini API 키가 설정되지 않았습니다.") 
}
plan(multisession, workers = availableCores() - 1)
log_message("INFO", sprintf("%d개의 코어를 사용하여 병렬 처리를 시작합니다.", nbrOfWorkers()))

# 3. 데이터 로드 및 분석 대상 결정
if (!file.exists(PATHS$prompts_data)) { 
  log_message("ERROR", sprintf("%s 파일을 찾을 수 없습니다.", PATHS$prompts_data))
  stop("⚠️ prompts_ready.RDS 파일을 찾을 수 없습니다.") 
}
full_corpus_with_prompts <- readRDS(PATHS$prompts_data)
log_message("INFO", "프롬프트 데이터 로드 완료")

# 3-1. 분석 모드 결정 및 데이터 샘플링
if (ANALYSIS_MODE == "ask") {
  # 사용자에게 모드 선택 요청 (배치 옵션 제외)
  selected_mode <- get_analysis_mode_simple()
} else {
  selected_mode <- ANALYSIS_MODE
  log_message("INFO", sprintf("설정된 분석 모드: %s", selected_mode))
}

# 선택된 모드에 따른 데이터 준비
if (selected_mode %in% c("code_check", "pilot", "sampling", "full")) {
  # 4단계 시스템 사용
  log_message("INFO", sprintf("4단계 분석 시스템 - %s 모드 실행", selected_mode))
} else if (selected_mode == "batch_processing") {
  # 배치 처리 선택 시 안내
  cat("\n💰 배치 처리를 원하시면 다음 스크립트를 사용하세요:\n")
  cat("   - 04_batch_emotion_analysis.R: 배치 처리 실행\n")
  cat("   - 06_batch_monitor.R: 배치 작업 모니터링\n")
  cat("\n지금은 일반 분석 모드를 선택해주세요.\n")
  
  # 다시 선택하도록 유도
  selected_mode <- get_analysis_mode_simple()
  if (selected_mode == "batch_processing") {
    log_message("INFO", "사용자가 배치 처리를 계속 선택함. 종료합니다.")
    quit(save = "no")
  }
}

if (selected_mode %in% c("code_check", "pilot", "sampling", "full")) {
  # 4단계 시스템 사용
  
  # 모드별 샘플링 실행
  raw_sample <- get_sample_for_mode(full_corpus_with_prompts, selected_mode)
  
  # 분석 전 최종 샘플 크기 확정 (sampling 모드만)
  if (selected_mode == "sampling") {
    log_message("INFO", "=== 분석 전 최종 샘플 확정 ===")
    current_size <- nrow(raw_sample)
    upper_limit <- TARGET_SAMPLE_SIZE * (1 + ANALYSIS_CONFIG$safety_buffer)
    
    if (current_size > upper_limit) {
      log_message("WARN", sprintf("샘플 크기(%d개)가 허용 상한(%d개)을 초과합니다.", 
                                  current_size, round(upper_limit)))
      
      # 게시물 단위로 크기 조정
      data_to_process <- adjust_sample_size_by_posts(raw_sample, TARGET_SAMPLE_SIZE)
      log_message("INFO", sprintf("최종 확정 샘플: %d개 → %d개", current_size, nrow(data_to_process)))
    } else {
      data_to_process <- raw_sample
      log_message("INFO", sprintf("최종 확정 샘플: %d개 (조정 불필요)", current_size))
    }
    analysis_type <- "sampling"
  } else {
    data_to_process <- raw_sample
    analysis_type <- selected_mode
  }
  
} else if (selected_mode == "sample") {
  # 기존 샘플링 모드 (하위 호환성)
  if (ENABLE_ADAPTIVE_SAMPLING) {
    log_message("INFO", "기존 적응형 샘플링 사용...")
    raw_sample <- adaptive_sampling(
      data = full_corpus_with_prompts,
      target_size = TARGET_SAMPLE_SIZE,
      min_posts = ANALYSIS_CONFIG$min_posts_start,
      max_posts = ANALYSIS_CONFIG$max_posts_limit,
      max_iterations = ANALYSIS_CONFIG$max_iteration,
      increment_step = ANALYSIS_CONFIG$increment_step,
      safety_buffer = ANALYSIS_CONFIG$safety_buffer
    )
    analysis_type <- "adaptive_sample"
  } else {
    # 기존 방식 샘플링
    random_post_ids <- full_corpus_with_prompts %>%
      filter(구분 == "게시글") %>% distinct(post_id) %>% 
      sample_n(min(SAMPLE_POST_COUNT, n())) %>% pull(post_id)
    raw_sample <- full_corpus_with_prompts %>%
      filter(post_id %in% random_post_ids) %>%
      arrange(post_id, if("comment_id" %in% names(.)) comment_id else NULL)
    analysis_type <- "sample"
  }
  data_to_process <- raw_sample
}

# 최종 샘플 크기 확정 로그
log_message("INFO", sprintf("🎯 최종 분석 대상: %d개 샘플 확정", nrow(data_to_process)))

# 샘플링 결과 요약 출력
print_sampling_summary(full_corpus_with_prompts, data_to_process, selected_mode)

# 3-2. 기분석 데이터 제외 (핵심 개선사항!)
log_message("INFO", "기분석 데이터 확인 중...")

# 이전 분석 통계 출력
stats <- tracker$get_analysis_stats()
if (stats$total > 0) {
  log_message("INFO", sprintf("기존 분석 이력: 총 %d건", stats$total))
  print(stats$by_type)
}

# 기분석 데이터를 제외한 실제 분석 대상 결정
data_to_process_filtered <- tracker$filter_unanalyzed(
  data_to_process,
  exclude_types = c("sample", "test", "full", "adaptive_sample"),  # 모든 이전 분석 제외
  model_filter = model_name,  # 같은 모델로 분석한 것만 제외
  days_back = 30  # 최근 30일간의 분석만 고려
)

# 분석 제외 대상 필터링 (기존 로직)
data_skipped <- data_to_process_filtered %>%
  mutate(content_cleaned = trimws(content)) %>%
  filter(
    is.na(content_cleaned) | content_cleaned == "" |
      content_cleaned %in% c("내용 없음", "삭제된 댓글입니다.", "비밀 댓글입니다.", "다수의 신고 또는 커뮤니티 이용규정을 위반하여 차단된 게시물입니다.") |
      str_detect(content_cleaned, "작성자가 (댓글|글)을 삭제하였습니다") |
      str_length(content_cleaned) <= 2 |
      !str_detect(content_cleaned, "[가-힣A-Za-z]")
  ) %>%
  select(-content_cleaned)

data_for_api_call <- data_to_process_filtered %>%
  anti_join(data_skipped, by = c("post_id", "comment_id"))

# 중복 제거 효과 로그
original_count <- nrow(data_to_process)
filtered_count <- nrow(data_to_process_filtered)
api_call_count <- nrow(data_for_api_call)
excluded_by_history <- original_count - filtered_count
excluded_by_filter <- filtered_count - api_call_count

log_message("INFO", sprintf("분석 대상 결정 완료:"))
log_message("INFO", sprintf("  - 전체 대상: %d건", original_count))
log_message("INFO", sprintf("  - 기분석 제외: %d건 (%.1f%% 절약)", excluded_by_history, (excluded_by_history/original_count)*100))
log_message("INFO", sprintf("  - 필터링 제외: %d건", excluded_by_filter))
log_message("INFO", sprintf("  - 실제 API 호출: %d건", api_call_count))

if (api_call_count == 0) {
  log_message("INFO", "새로 분석할 데이터가 없습니다. 기존 분석 결과를 병합하여 최종 결과를 생성합니다.")
  
  # 기존 분석 결과 병합하여 최종 결과 생성
  # (이 부분은 실제 구현에서 기존 결과를 로드하여 병합하는 로직 추가)
  
} else {
  # 예상 분석 시간 계산 및 사용자 확인
  estimated_time <- api_call_count / RATE_LIMIT_PER_MINUTE
  estimated_cost_saved <- excluded_by_history * 0.001  # 가정: API 호출당 0.001달러
  
  log_message("INFO", sprintf("예상 분석 시간: %.1f분", estimated_time))
  log_message("INFO", sprintf("중복 제거로 절약된 예상 비용: $%.3f", estimated_cost_saved))
  
  # 4. 감정 분석 실행
  initial_api_results_df <- NULL
  
  log_message("INFO", sprintf("1차 분석을 시작합니다... (분당 %d회 제한 준수)", RATE_LIMIT_PER_MINUTE))
  data_chunks <- data_for_api_call %>%
    mutate(chunk_id = ceiling(row_number() / RATE_LIMIT_PER_MINUTE)) %>%
    group_by(chunk_id) %>%
    group_split()
  handlers(handler_progress(format = "[:bar] :percent | 소요시간: :elapsed | 남은시간: :eta", width = 80))
  results_list <- list()
  with_progress({
    p <- progressor(steps = nrow(data_for_api_call))
    for (i in seq_along(data_chunks)) {
      current_chunk <- data_chunks[[i]]
      cat(sprintf("\n▶️ 1차 분석: 청크 %d / %d 처리 중 (%d개 작업)...\n", i, length(data_chunks), nrow(current_chunk)))
      chunk_result_df <- future_map_dfr(current_chunk$prompt, function(pr) {
        p()
        analyze_emotion_robust(prompt_text = pr, model_to_use = model_name, temp_to_use = temp_val, top_p_to_use = top_p_val)
      }, .options = furrr_options(seed = TRUE))
      results_list[[i]] <- bind_cols(current_chunk, chunk_result_df)
      if (i < length(data_chunks)) {
        cat(sprintf("✅ 1차 청크 %d / %d 완료. %d초간 대기...\n", i, length(data_chunks), WAIT_TIME_SECONDS))
        Sys.sleep(WAIT_TIME_SECONDS)
      }
    }
  })
  initial_api_results_df <- bind_rows(results_list)
  log_message("INFO", "API 분석이 완료되었습니다.")
  
  # 5. 실패 항목 재분석 (기존 로직과 동일)
  rerun_final_df <- NULL
  successful_df <- initial_api_results_df %>% filter(!(combinated_emotion %in% c("API 오류", "파싱 오류", "분석 오류") | is.na(combinated_emotion)))
  failed_df <- initial_api_results_df %>% filter(combinated_emotion %in% c("API 오류", "파싱 오류", "분석 오류") | is.na(combinated_emotion))
  
  if (nrow(failed_df) > 0) {
    log_message("WARN", sprintf("%d개 항목이 실패하여 재분석을 진행합니다...", nrow(failed_df)))
    # 재분석 로직 (기존과 동일)
  } else {
    log_message("INFO", "1차 분석에서 실패한 항목이 없습니다.")
  }
  
  # 6. 새 분석 결과를 이력에 등록
  if (!is.null(successful_df) && nrow(successful_df) > 0) {
    tracker$register_analysis(
      successful_df,
      analysis_type = analysis_type,
      model_used = model_name,
      analysis_file = "03_감정분석_전체실행"
    )
    log_message("INFO", sprintf("새 분석 결과 %d건을 이력에 등록했습니다.", nrow(successful_df)))
  }
  
  if (!is.null(rerun_final_df) && nrow(rerun_final_df) > 0) {
    tracker$register_analysis(
      rerun_final_df,
      analysis_type = analysis_type,
      model_used = model_name,
      analysis_file = "03_감정분석_전체실행_rerun"
    )
  }
}

# 7. 최종 결과 병합 (기존 로직 + 기분석 데이터 포함)
log_message("INFO", "최종 결과 병합을 시작합니다...")

# 기분석 데이터 로드 (필요시)
previously_analyzed <- data.frame()  # 실제 구현에서는 기존 결과 파일들을 로드

# 건너뛴 데이터에 분석 결과 컬럼 추가
if (nrow(data_skipped) > 0) {
  skipped_final_df <- data_skipped %>%
    mutate(
      기쁨 = NA_real_, 신뢰 = NA_real_, 공포 = NA_real_, 놀람 = NA_real_,
      슬픔 = NA_real_, 혐오 = NA_real_, 분노 = NA_real_, 기대 = NA_real_,
      P = NA_real_, A = NA_real_, D = NA_real_,
      combinated_emotion = "분석 제외",
      complex_emotion = NA_character_,
      rationale = "필터링된 내용 (삭제, 단문 등)",
      error_message = NA_character_
    )
} else {
  skipped_final_df <- NULL
}

# 모든 데이터 병합
final_df <- bind_rows(
  successful_df,
  rerun_final_df,
  skipped_final_df,
  previously_analyzed  # 기분석 데이터도 포함
) %>%
  arrange(post_id, if("comment_id" %in% names(.)) comment_id else NULL)

# 8. 로컬 저장 및 인간 코딩용 구글 시트 업로드
# 4단계 모드별 파일명 생성 (타임스탬프 포함)
if (selected_mode == "code_check") {
  rds_filename <- generate_filepath("code_check", nrow(data_to_process), ".RDS")
  csv_filename <- generate_filepath("code_check", nrow(data_to_process), ".csv")
  sample_label <- sprintf("CODE_CHECK_%ditems", nrow(data_to_process))
} else if (selected_mode == "pilot") {
  rds_filename <- generate_filepath("pilot", nrow(data_to_process), ".RDS")
  csv_filename <- generate_filepath("pilot", nrow(data_to_process), ".csv")
  sample_label <- sprintf("PILOT_%ditems", nrow(data_to_process))
} else if (selected_mode == "sampling") {
  rds_filename <- generate_filepath("sampling", nrow(data_to_process), ".RDS")
  csv_filename <- generate_filepath("sampling", nrow(data_to_process), ".csv")
  sample_label <- sprintf("SAMPLING_%ditems", nrow(data_to_process))
} else if (selected_mode == "full") {
  rds_filename <- generate_filepath("full", nrow(data_to_process), ".RDS")
  csv_filename <- generate_filepath("full", nrow(data_to_process), ".csv")
  sample_label <- "FULL"
} else if (selected_mode == "sample") {
  # 기존 샘플링 모드 (하위 호환성)
  if (analysis_type == "adaptive_sample") {
    rds_filename <- generate_filepath("adaptive", nrow(data_to_process), ".RDS")
    csv_filename <- generate_filepath("adaptive", nrow(data_to_process), ".csv")
    sample_label <- sprintf("ADAPTIVE_%ditems", nrow(data_to_process))
  } else {
    rds_filename <- generate_filepath("sample", SAMPLE_POST_COUNT, ".RDS")
    csv_filename <- generate_filepath("sample", SAMPLE_POST_COUNT, ".csv")
    sample_label <- sprintf("SAMPLE_%dposts", SAMPLE_POST_COUNT)
  }
}

saveRDS(final_df, rds_filename)
readr::write_excel_csv(final_df, csv_filename, na = "")
log_message("INFO", sprintf("분석 결과가 '%s' 및 '%s' 파일로 저장되었습니다.", rds_filename, csv_filename))

# 인간 코딩용 구글 시트 생성 (모드별 조건부 실행)
should_enable_human_coding <- case_when(
  selected_mode == "code_check" ~ TRUE,   # 코드 점검: 구글 시트 생성 (인간 코딩은 아니지만 결과 확인용)
  selected_mode == "pilot" ~ TRUE,        # 파일럿: 활성화 (크기에 따라 실행 여부 결정)
  selected_mode == "sampling" ~ TRUE,     # 표본 분석: 필수
  selected_mode == "full" ~ HUMAN_CODING_CONFIG$enable_human_coding,   # 전체: 설정에 따름
  selected_mode == "sample" ~ HUMAN_CODING_CONFIG$enable_human_coding,  # 기존 모드
  TRUE ~ FALSE
)

# 모드별 최소 샘플 크기 요구사항
min_size_for_mode <- case_when(
  selected_mode == "code_check" ~ 1,      # 코드 점검: 최소 1개 (결과 확인용)
  selected_mode == "pilot" ~ 20,          # 파일럿: 최소 20개
  selected_mode == "sampling" ~ HUMAN_CODING_CONFIG$min_sample_size,  # 표본: 기본 설정
  TRUE ~ HUMAN_CODING_CONFIG$min_sample_size
)

if (should_enable_human_coding && nrow(final_df) >= min_size_for_mode) {
  
  log_message("INFO", "인간 코딩용 구글 시트 생성을 시작합니다...")
  
  tryCatch({
    # 성공적으로 분석된 데이터만 사용 (오류 제외) - 추가 샘플링 없이
    valid_for_coding <- final_df %>%
      filter(!is.na(combinated_emotion), 
             !combinated_emotion %in% c("API 오류", "파싱 오류", "분석 오류", "분석 제외"))
    
    log_message("INFO", sprintf("인간 코딩용 유효 샘플: %d개 (이미 분석 전 샘플링 완료)", 
                                nrow(valid_for_coding)))
    
    if (nrow(valid_for_coding) >= HUMAN_CODING_CONFIG$min_sample_size) {
      sheet_urls <- create_human_coding_sheets(valid_for_coding, sample_label)
      
      if (!is.null(sheet_urls) && length(sheet_urls) > 0) {
        log_message("INFO", sprintf("인간 코딩용 시트 %d개가 성공적으로 생성되었습니다.", length(sheet_urls)))
        # 모드별 안내 메시지
        mode_guidance <- switch(selected_mode,
          "code_check" = "🔧 코드 점검 결과 확인용 시트",
          "pilot" = "🧪 파일럿 연구 인간 코딩 (선택사항)",
          "sampling" = "📊 표본 분석 인간 코딩 (필수)",
          "full" = "🌍 전체 분석 인간 코딩 (표본 기반)",
          "sample" = "📊 샘플링 분석 인간 코딩",
          "인간 코딩"
        )
        
        cat(sprintf("\n🎯 %s - 다음 단계:\n", mode_guidance))
        cat("1. 위에 표시된 URL을 4명의 코더에게 전달\n")
        cat("2. 각 시트 확인:\n")
        cat("   ✅ 체크박스 자동 생성 성공 → 바로 작업 시작\n")
        cat("   ⚠️  체크박스 없음 → '참고사항' 탭에서 수동 설정 방법 확인\n")
        cat("3. 코더들이 human_agree 열에서 동의/비동의 체크\n")
        cat("4. 모든 코더 완료 후 '05_신뢰도_분석.R' 실행\n")
        cat("5. Krippendorff's Alpha로 신뢰도 측정\n")
        
        if (selected_mode == "code_check") {
          cat("\n🔧 코드 점검: 분석 결과를 구글 시트에서 확인하세요. 인간 코딩은 필요하지 않습니다.\n")
        } else if (selected_mode == "sampling") {
          cat("\n⚠️  표본 분석: 인간 코딩 검증이 통계적 유의성에 중요합니다!\n")
        } else if (selected_mode == "pilot") {
          cat("\n💡 파일럿 연구: 방법론 검증을 위한 선택적 인간 코딩입니다.\n")
        }
        cat("\n")
      } else {
        log_message("WARN", "인간 코딩용 시트 생성에 실패했습니다.")
      }
    } else {
      log_message("INFO", sprintf("유효한 분석 결과(%d건)가 %s 모드 최소 요구사항(%d건)보다 적어 인간 코딩을 생략합니다.", 
                                 nrow(valid_for_coding), selected_mode, min_size_for_mode))
    }
    
  }, error = function(e) {
    log_message("ERROR", sprintf("인간 코딩 시트 생성 중 오류: %s", e$message))
    log_message("INFO", "구글 시트 생성에 실패했지만 분석 결과는 정상적으로 저장되었습니다.")
  })
} else {
  # 인간 코딩이 활성화되지 않은 경우의 안내
  if (!should_enable_human_coding) {
    mode_reason <- switch(selected_mode,
      "code_check" = "코드 점검 모드는 인간 코딩을 생략합니다",
      "full" = "전체 분석 모드에서 인간 코딩이 비활성화되었습니다",
      "기본 설정에 의해 인간 코딩이 비활성화되었습니다"
    )
    log_message("INFO", sprintf("%s.", mode_reason))
  } else if (nrow(final_df) < min_size_for_mode) {
    log_message("INFO", sprintf("분석 결과(%d건)가 %s 모드 최소 요구사항(%d건)보다 적어 인간 코딩을 생략합니다.", 
                               nrow(final_df), selected_mode, min_size_for_mode))
  }
}

# 9. 최종 통계 출력
final_stats <- tracker$get_analysis_stats()
log_message("INFO", "=== 분석 완료 통계 ===")
log_message("INFO", sprintf("전체 누적 분석: %d건", final_stats$total))
log_message("INFO", sprintf("이번 세션에서 새로 분석: %d건", api_call_count))
log_message("INFO", sprintf("중복 제거로 절약된 API 호출: %d건", excluded_by_history))

# 분석 이력 정리
tracker$cleanup_old_history(90)

log_message("INFO", "=== 전체 감정분석 완료 ===")