# 데이터 불러오기 및 프롬프트 생성 (복구 시스템 적용)
# 목적: CSV 데이터를 불러오고 API 요청용 프롬프트 생성, RDS 저장

# 설정 및 유틸리티 로드
source("config.R")
source("utils.R")
source("recovery_system.R")

source(PATHS$functions_file, encoding = "UTF-8")

# 1. 패키지 로드
required_packages <- c("dplyr", "purrr", "readr", "R6")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages)
}
lapply(required_packages, library, character.only = TRUE)
log_message("INFO", "패키지 로드 완료")

# 복구 시스템 초기화
script_name <- "01_data_loading"

# 2. 데이터 로드 (복구 적용)
corpus_df <- with_recovery("load_data", script_name, function() {
  log_message("INFO", "=== 데이터 로드 시작 ===")
  
  if (!file.exists(PATHS$source_data)) {
    stop(sprintf("'%s' 파일을 찾을 수 없습니다.", PATHS$source_data))
  }
  
  # 데이터 로드 및 검증
  df <- read_csv(PATHS$source_data, col_types = cols(.default = "c"))
  
  # 데이터 품질 검증
  required_columns <- c("post_id", "content", "구분")
  if (!validate_data(df, required_columns, min_rows = 1)) {
    stop("데이터 검증 실패")
  }
  
  # 숫자 컬럼 변환
  df <- df %>%
    mutate(across(c(post_id, comment_id, depth, views, likes), as.numeric))
  
  log_message("INFO", sprintf("데이터 로드 완료: %d행, %d컬럼", nrow(df), ncol(df)))
  return(df)
})

# 3. 게시글 정보 추출 (복구 적용)
posts_lookup <- with_recovery("extract_posts", script_name, function() {
  log_message("INFO", "게시글 정보 추출 중...")
  
  posts_info <- corpus_df %>%
    filter(구분 == "게시글") %>%
    select(post_id, post_title = title, post_context = content)
  
  log_message("INFO", sprintf("게시글 정보 추출 완료: %d개 게시글", nrow(posts_info)))
  return(posts_info)
})

# 4. 프롬프트 생성 (배치 처리로 복구 적용)
corpus_with_prompts <- process_with_batch_recovery(
  data = corpus_df,
  process_function = function(batch_data) {
    # 배치별 프롬프트 생성
    batch_with_lookup <- batch_data %>%
      left_join(posts_lookup, by = "post_id")
    
    batch_with_prompts <- batch_with_lookup %>%
      mutate(
        prompt = purrr::pmap_chr(
          list(
            text = content,
            구분 = 구분,
            title = if_else(구분 == "게시글", title, NA_character_),
            context = post_context,
            context_title = post_title
          ),
          create_analysis_prompt
        )
      ) %>%
      select(-post_context, -post_title)
    
    return(batch_with_prompts)
  },
  batch_size = 1000,  # 프롬프트 생성은 빠르므로 큰 배치 사용
  checkpoint_name = "prompt_generation",
  script_name = script_name
)

# 5. 최종 검증 및 저장
final_result <- with_recovery("final_validation", script_name, function() {
  log_message("INFO", "최종 데이터 검증 중...")
  
  # 프롬프트 생성 검증
  if (any(is.na(corpus_with_prompts$prompt) | corpus_with_prompts$prompt == "")) {
    failed_count <- sum(is.na(corpus_with_prompts$prompt) | corpus_with_prompts$prompt == "")
    log_message("WARN", sprintf("프롬프트 생성 실패: %d건", failed_count))
  }
  
  # 데이터 무결성 검증
  if (nrow(corpus_with_prompts) != nrow(corpus_df)) {
    log_message("ERROR", "데이터 행 수 불일치")
    stop("프롬프트 생성 과정에서 데이터 손실 발생")
  }
  
  log_message("INFO", sprintf("최종 검증 완료: %d행의 프롬프트 생성", nrow(corpus_with_prompts)))
  return(corpus_with_prompts)
})

# 6. RDS 저장
saveRDS(final_result, file = PATHS$prompts_data)
log_message("INFO", sprintf("'%s' 저장 완료", PATHS$prompts_data))

# 체크포인트 정리
if (RECOVERY_CONFIG$enable_checkpoints) {
  checkpoint_manager <- CheckpointManager$new(script_name)
  checkpoint_manager$cleanup_old_checkpoints(RECOVERY_CONFIG$cleanup_days)
}

log_message("INFO", "=== 데이터 로드 및 프롬프트 생성 완료 ===")
log_message("INFO", "다음: 02_단건분석_테스트.R 실행")