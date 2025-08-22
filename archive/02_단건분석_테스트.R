# 단건 분석 테스트
# 목적: RDS 파일에서 샘플 1개 선택하여 감정분석 테스트

# 설정 및 유틸리티 로드
source("config.R")
source("utils.R")

# 1. 패키지 로드
required_packages <- c("dplyr", "stringr", "jsonlite")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)
cat("✅ 패키지 로드 완료\n\n")

# 공통 함수 로드
source(PATHS$functions_file, encoding = "UTF-8")

# 2. API 설정
readRenviron("~/.Renviron")
setAPI(Sys.getenv("GEMINI_API_KEY"))
# 테스트 설정에서 모델 매개변수 로드
model_name <- TEST_CONFIG$model_name
temp_val <- TEST_CONFIG$temperature
top_p_val <- TEST_CONFIG$top_p

# 3. 데이터 로드 및 샘플링
log_message("INFO", "=== 단건 분석 테스트 시작 ===")

if (!file.exists(PATHS$prompts_data)) {
  log_message("ERROR", sprintf("%s 파일을 찾을 수 없습니다.", PATHS$prompts_data))
  stop("01_데이터_불러오기_프롬프트_생성.R 먼저 실행해주세요.")
}
full_corpus_with_prompts <- readRDS(PATHS$prompts_data)
log_message("INFO", "RDS 파일 로드 완료")

set.seed(as.integer(Sys.time()))
single_sample_df <- full_corpus_with_prompts %>%
  sample_n(1)
log_message("INFO", sprintf("샘플 1개 추출 완료 (ID: %s)", single_sample_df$post_id[1]))

# 4. 감정 분석 실행
log_message("INFO", "감정 분석 API 호출 시작")

prompt_to_analyze <- single_sample_df$prompt

# API 호출
analysis_result_df <- time_execution({
  analyze_emotion_robust(
    prompt_text = prompt_to_analyze,
    model_to_use = model_name,
    temp_to_use = temp_val,
    top_p_to_use = top_p_val
  )
}, "API 호출")

# 5. 결과 출력
final_single_df <- bind_cols(single_sample_df, analysis_result_df)

log_message("INFO", "분석 완료 - 결과 출력 시작")
cat("--------------------------------------------------\n")

# 원본 내용
cat("▶️ 분석 대상:\n")
cat(paste0("  ", single_sample_df$content), "\n\n")

# 분석 결과
cat("▶️ 분석 결과:\n")
if (!is.na(final_single_df$error_message)) {
  # 에러 발생 시
  cat("  - 에러 발생:", final_single_df$dominant_emotion, "\n")
  cat("  - 에러 내용:", final_single_df$error_message, "\n")
} else {
  # 분석 성공 시
  
  # 8대 감정 점수
  cat("  - 8대 감정 점수:\n")
  main_scores <- final_single_df %>% select(기쁨:중립)
  print(main_scores, row.names = FALSE)
  cat("\n")
  
  # PAD 모델 점수
  cat("  - PAD 모델 점수:\n")
  pad_scores <- final_single_df %>% select(P, A, D)
  print(pad_scores, row.names = FALSE)
  cat("\n")
  
  cat("  - 지배 감정:", final_single_df$dominant_emotion, "\n")
  cat("  - 복합 감정 (PAD):", final_single_df$PAD_complex_emotion, "\n\n")
  
  cat("  - 분석 근거:", final_single_df$rationale, "\n\n")
  # 추가 감정
  if (!is.na(final_single_df$unexpected_emotions)) {
    cat("  - 추가 감정:\n")
    cat("   ", final_single_df$unexpected_emotions, "\n")
  }
}

# 마무리
log_message("INFO", "=== 단건 분석 테스트 완료 ===")
cat("--------------------------------------------------\n")