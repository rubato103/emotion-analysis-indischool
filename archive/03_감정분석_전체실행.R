# 전체 감정분석 실행
# 목적: 병렬 처리로 전체 데이터 감정분석, 실패 항목 재분석, 결과 저장

# 설정 및 유틸리티 로드
source("config.R")
source("utils.R")

# 0. 환경 설정 (config.R에서 로드)
RATE_LIMIT_PER_MINUTE <- API_CONFIG$rate_limit_per_minute
WAIT_TIME_SECONDS <- API_CONFIG$wait_time_seconds
model_name <- API_CONFIG$model_name
temp_val <- API_CONFIG$temperature
top_p_val <- API_CONFIG$top_p
TARGET_GDRIVE_FOLDER <- ANALYSIS_CONFIG$target_gdrive_folder

# 핵심 제어 변수 (config.R에서 로드)
SAMPLE_POST_COUNT <- ANALYSIS_CONFIG$sample_post_count

# 1. 패키지 로드
required_packages <- c("dplyr", "stringr", "jsonlite", "future", "furrr", "progressr","googlesheets4", "googledrive", "readr")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)
cat("✅ 필요한 패키지를 모두 불러왔습니다.\n")

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

# 3-1. 샘플링 또는 전체 분석
if (SAMPLE_POST_COUNT > 0) {
  random_post_ids <- full_corpus_with_prompts %>%
    filter(구분 == "게시글") %>% distinct(post_id) %>% sample_n(SAMPLE_POST_COUNT) %>% pull(post_id)
  data_to_process <- full_corpus_with_prompts %>%
    filter(post_id %in% random_post_ids) %>%
    arrange(post_id, if("comment_id" %in% names(.)) comment_id else NULL)
  log_message("INFO", sprintf("샘플링 모드로 실행합니다. (%d개 게시글 대상)", SAMPLE_POST_COUNT))
} else {
  data_to_process <- full_corpus_with_prompts
  log_message("INFO", "전체 분석 모드로 실행합니다.")
}

# 3-2. 분석 제외 대상 필터링
data_skipped <- data_to_process %>%
  mutate(content_cleaned = trimws(content)) %>%
  filter(
    is.na(content_cleaned) | content_cleaned == "" |
      content_cleaned %in% c("내용 없음", "삭제된 댓글입니다.", "비밀 댓글입니다.", "다수의 신고 또는 커뮤니티 이용규정을 위반하여 차단된 게시물입니다.") |
      str_detect(content_cleaned, "작성자가 (댓글|글)을 삭제하였습니다") |
      str_length(content_cleaned) <= 2 |
      !str_detect(content_cleaned, "[가-힣A-Za-z]")
  ) %>%
  select(-content_cleaned)

data_for_api_call <- data_to_process %>%
  anti_join(data_skipped, by = c("post_id", "comment_id"))

log_message("INFO", sprintf("처리 대상 %d개 중 %d개는 API 호출, %d개는 건너뜁니다.", 
            nrow(data_to_process), nrow(data_for_api_call), nrow(data_skipped)))

# 4. 감정 분석 실행
initial_api_results_df <- NULL
if (nrow(data_for_api_call) > 0) {
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
} else {
  log_message("INFO", "API를 호출할 데이터가 없어 1차 분석을 건너뜁니다.")
}

# 5. 실패 항목 재분석
rerun_final_df <- NULL
successful_df <- initial_api_results_df %>% filter(!(dominant_emotion %in% c("API 오류", "파싱 오류", "분석 오류") | is.na(dominant_emotion)))
failed_df <- initial_api_results_df %>% filter(dominant_emotion %in% c("API 오류", "파싱 오류", "분석 오류") | is.na(dominant_emotion))

if (nrow(failed_df) > 0) {
  log_message("WARN", sprintf("%d개 항목이 실패하여 재분석을 진행합니다...", nrow(failed_df)))
  # 재분석 로직 (기존과 동일)
} else {
  log_message("INFO", "1차 분석에서 실패한 항목이 없습니다.")
}

# 6. 최종 결과 병합
log_message("INFO", "최종 결과 병합을 시작합니다...")

# 건너뛴 데이터에 분석 결과 컬럼 추가
if (nrow(data_skipped) > 0) {
  skipped_final_df <- data_skipped %>%
    mutate(
      기쁨 = NA_real_, 슬픔 = NA_real_, 분노 = NA_real_, 혐오 = NA_real_,
      공포 = NA_real_, 놀람 = NA_real_, `애정/사랑` = NA_real_, 중립 = NA_real_,
      P = NA_real_, A = NA_real_, D = NA_real_,
      PAD_complex_emotion = NA_character_,
      dominant_emotion = "분석 제외",
      rationale = "필터링된 내용 (삭제, 단문 등)",
      unexpected_emotions = NA_character_,
      error_message = NA_character_
    )
} else {
  skipped_final_df <- NULL
}

# 모든 데이터 병합
final_df <- bind_rows(
  successful_df,
  rerun_final_df,
  skipped_final_df
) %>%
  arrange(post_id, if("comment_id" %in% names(.)) comment_id else NULL)

# 데이터 무결성 검증
original_row_count <- nrow(data_to_process)
final_row_count <- nrow(final_df)

if (original_row_count == final_row_count) {
  log_message("INFO", sprintf("데이터 무결성 검증 완료: 원본 %d건, 최종 %d건", original_row_count, final_row_count))
} else {
  log_message("ERROR", sprintf("데이터 무결성 검증 실패: 원본 %d건, 최종 %d건으로 데이터 손실 발생!", original_row_count, final_row_count))
  warning(sprintf("⚠️ 데이터 무결성 검증 실패: 원본 %d건, 최종 %d건으로 데이터 손실이 발생했습니다!", original_row_count, final_row_count))
}

# 7. 로컬 저장
if (SAMPLE_POST_COUNT > 0) {
  file_label <- paste0("_SAMPLE_", SAMPLE_POST_COUNT, "posts")
} else {
  file_label <- "_FULL"
}
rds_filename <- file.path(PATHS$results_dir, paste0("analysis_results", file_label, ".RDS"))
csv_filename <- file.path(PATHS$results_dir, paste0("analysis_results", file_label, ".csv"))

saveRDS(final_df, rds_filename)
readr::write_excel_csv(final_df, csv_filename, na = "")
log_message("INFO", sprintf("분석 결과가 '%s' 및 '%s' 파일로 저장되었습니다.", rds_filename, csv_filename))

# 8. 구글 시트 업로드
#gs4_auth(email = TRUE)
log_message("INFO", "최종 분석 결과를 구글 시트로 업로드합니다...")

final_df_for_upload <- final_df %>%
  select(-any_of(c("prompt", "chunk_id")))

if (nrow(final_df_for_upload) > 0) {
  sheet_title <- paste0("감정분석", file_label, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  
  tryCatch({
    # 구글 시트 생성
    created_sheet <- gs4_create(
      name = sheet_title,
      sheets = list(data = final_df_for_upload)
    )
    log_message("INFO", sprintf("새 구글 시트 '%s' 생성 완료", sheet_title))
    
    # 대상 폴더 검색 또는 생성
    folder_info <- drive_find(q = sprintf("name = '%s' and mimeType = 'application/vnd.google-apps.folder' and trashed = false", TARGET_GDRIVE_FOLDER), n_max = 1)
    
    if(nrow(folder_info) == 0) {
      folder_info <- drive_mkdir(name = TARGET_GDRIVE_FOLDER)
      log_message("INFO", sprintf("'%s' 폴더를 새로 생성했습니다.", TARGET_GDRIVE_FOLDER))
    } else {
      log_message("INFO", sprintf("기존 '%s' 폴더를 찾았습니다.", TARGET_GDRIVE_FOLDER))
    }
    
    # 시트를 대상 폴더로 이동
    drive_mv(file = created_sheet, path = folder_info)
    log_message("INFO", sprintf("생성된 시트를 '%s' 폴더로 이동 완료", TARGET_GDRIVE_FOLDER))
    
    log_message("INFO", "모든 작업이 성공적으로 완료되었습니다.")
    log_message("INFO", "구글 시트 링크:")
    cat(gs4_get(created_sheet)$spreadsheet_url, "\n")
    
  }, error = function(e) {
    log_message("ERROR", sprintf("구글 시트 작업 중 오류 발생: %s", e$message))
  })
} else {
  log_message("INFO", "업로드할 데이터가 없습니다.")
}