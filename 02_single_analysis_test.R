# 단건 분석 테스트 (분석 이력 추적 적용)
# 목적: Parquet 파일에서 샘플 1개 선택하여 감정분석 테스트, 결과 이력 저장

# 통합 초기화 시스템 로드 (Parquet 전용)
source("libs/init.R")
source("libs/utils.R")
source("modules/analysis_tracker.R")
source("modules/human_coding.R")

# 1. 패키지 로드
required_packages <- c("dplyr", "stringr", "jsonlite", "R6", "gemini.R")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)
log_message("INFO", "패키지 로드 완료 (gemini.R 패키지 사용)")

# 분석 이력 추적기 초기화
tracker <- AnalysisTracker$new()

# 공통 함수 로드
source(PATHS$functions_file, encoding = "UTF-8")

# 2. API 설정
if (Sys.getenv("GEMINI_API_KEY") == "") { 
  log_message("ERROR", "Gemini API 키가 설정되지 않았습니다.")
  stop("⚠️ Gemini API 키가 설정되지 않았습니다. 시스템 환경변수를 확인하세요.") 
}
log_message("INFO", "API 키 확인 완료 (gemini.R 패키지 사용)")
# 테스트 설정에서 모델 매개변수 로드
model_name <- TEST_CONFIG$model_name
temp_val <- TEST_CONFIG$temperature
top_p_val <- TEST_CONFIG$top_p

# 3. 데이터 로드 및 샘플링
log_message("INFO", "=== 단건 분석 테스트 시작 ===")

tryCatch({
  full_corpus_with_prompts <- load_prompts_data()
  log_message("INFO", "Parquet 파일 로드 완료")
}, error = function(e) {
  log_message("ERROR", "data/prompts_ready 파일을 찾을 수 없습니다.")
  stop("01_data_loading_and_prompt_generation.R 먼저 실행해주세요.")
})

# 기분석 데이터 제외한 샘플링
unanalyzed_data <- tracker$filter_unanalyzed(
  full_corpus_with_prompts, 
  exclude_types = c("test", "sample"),  # 이전 테스트나 샘플 분석 제외
  model_filter = model_name,  # 같은 모델로 분석한 것만 제외
  days_back = 7  # 최근 7일간의 분석만 고려
)

if (nrow(unanalyzed_data) == 0) {
  log_message("WARN", "모든 데이터가 이미 분석되었습니다.")
  
  # 분석 통계 출력
  stats <- tracker$get_analysis_stats()
  log_message("INFO", sprintf("총 분석 건수: %d건", stats$total))
  print(stats$by_type)
  
  stop("새로 분석할 데이터가 없습니다. 전체 데이터를 대상으로 하려면 analysis_history를 삭제하세요.")
}

# 미분석 데이터에서 랜덤 샘플링
set.seed(as.integer(Sys.time()))
single_sample_df <- unanalyzed_data %>%
  sample_n(1)
log_message("INFO", sprintf("미분석 데이터에서 샘플 1개 추출 완료 (ID: %s)", single_sample_df$post_id[1]))

# 4. 감정 분석 실행
log_message("INFO", "감정 분석 API 호출 시작")

prompt_to_analyze <- single_sample_df$prompt

# API 호출
analysis_result_df <- time_execution({
  analyze_emotion_robust(
  prompt_text = prompt_to_analyze,
  model_to_use = API_CONFIG$model_name,
  temp_to_use = API_CONFIG$temperature,
  top_p_to_use = API_CONFIG$top_p
)
}, "API 호출")

# 5. 결과 출력 및 이력 저장
final_single_df <- bind_cols(single_sample_df, analysis_result_df)

# 분석 결과를 이력에 등록
tracker$register_analysis(
  final_single_df, 
  analysis_type = "test",
  model_used = model_name,
  analysis_file = "02_단건분석_테스트"
)

log_message("INFO", "분석 완료 - 결과 출력 시작")
cat("--------------------------------------------------\n")

# 원본 내용
cat("▶️ 분석 대상:\n")
cat(paste0("  ", single_sample_df$content), "\n\n")

# 분석 결과
cat("▶️ 분석 결과:\n")
if (!is.na(final_single_df$error_message)) {
  # 에러 발생 시
  cat("  - 에러 발생:", final_single_df$combinated_emotion, "\n")
  cat("  - 에러 내용:", final_single_df$error_message, "\n")
} else {
  # 분석 성공 시
  
  # 점수 출력용 헬퍼 함수
  print_scores <- function(df, title) {
    cat(paste0("  - ", title, ":\n"))
    for (col_name in names(df)) {
      cat(sprintf("    %-10s: %.3f\n", col_name, df[[col_name]]))
    }
    cat("\n")
  }

  # 플루치크 8대 기본감정 점수 출력
  plutchik_scores <- final_single_df %>% select(기쁨, 신뢰, 공포, 놀람, 슬픔, 혐오, 분노, 기대)
  print_scores(plutchik_scores, "플루치크 8대 기본감정 점수")

  # PAD 모델 점수 출력
  pad_scores <- final_single_df %>% select(P, A, D)
  print_scores(pad_scores, "PAD 모델 점수")
  
  # 감정 대상 출력
  if (!is.na(final_single_df$emotion_source) && !is.na(final_single_df$emotion_direction)) {
    cat("  - 감정 유발 원인:", final_single_df$emotion_source, "\n")
    cat("  - 감정 향하는 방향:", final_single_df$emotion_direction, "\n")
  }
  
  cat("  - 조합 감정:", final_single_df$combinated_emotion, "\n")
  cat("  - 복합 감정:", final_single_df$complex_emotion, "\n\n")
  
  # 분석 근거 출력 (통합된 근거)
  cat("  - 분석 근거:\n")
  if (!is.na(final_single_df$rationale)) {
    cat(paste0("    ", strwrap(final_single_df$rationale, width = 75)), sep = "\n")
  }
  cat("\n")
}

# 분석 통계 출력 (기존과 동일하게 가독성 좋음)
stats <- tracker$get_analysis_stats()
cat("\n▶️ 누적 분석 통계:\n")
cat(sprintf("  - 총 분석 건수: %d건\n", stats$total))
if (nrow(stats$by_type) > 0) {
  cat("  - 분석 유형별:\n")
  for(i in 1:nrow(stats$by_type)) {
    cat(sprintf("    %s: %d건 (최근: %s)\n", 
                stats$by_type$analysis_type[i], 
                stats$by_type$count[i],
                format(stats$by_type$latest_analysis[i], "%Y-%m-%d %H:%M")))
  }
}

# 마무리
log_message("INFO", "=== 단건 분석 테스트 완료 ===")
cat("--------------------------------------------------\n")
