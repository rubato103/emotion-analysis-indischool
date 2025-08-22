# 최종 함수 테스트

# 설정 및 함수 로드
source("config.R")
source("utils.R")
source("functions_final.R")

# 패키지 로드
library(dplyr)
library(jsonlite)

cat("✅ 최종 함수 테스트 시작\n")

# 테스트 프롬프트
test_prompt <- paste0(
  "## 역할: 고도로 훈련된 리서치 보조원\n",
  "## 컨텍스트: 모든 텍스트는 직업인증이 필요한 초등교사 커뮤니티에서 수집됨.\n",
  "## 지시:\n",
  "1. **감정 점수 (0.00~1.00)**: 8개 감정(기쁨, 슬픔, 분노, 혐오, 공포, 놀람, 애정/사랑, 중립) 평가.\n",
  "2. **PAD 모델 점수 (-1.00~1.00)**: P(쾌락/긍정성), A(각성/활성도), D(지배/통제감) 평가.\n",
  "3. **결과 명명**: PAD 점수 기반 \"복합 감정\" 명명 및 최고점 감정을 \"지배 감정\"으로 선정.\n",
  "4. **분석 근거 제시**: 모든 평가 점수 및 결과에 대한 논리적 근거를 서술.\n\n",
  "## 분석 과업: 다음 '게시글'의 감정을 분석.\n\n",
  "# 분석할 게시글 (분석 대상)\n",
  "오늘 정말 힘든 하루였어요. 학생들이 말을 안 들어서 스트레스가 많았습니다."
)

cat("📝 분석 시작...\n")
start_time <- Sys.time()

# 최종 함수로 분석
result <- analyze_emotion_final(
  prompt_text = test_prompt,
  model_to_use = API_CONFIG$model_name,
  temp_to_use = API_CONFIG$temperature,
  top_p_to_use = API_CONFIG$top_p
)

end_time <- Sys.time()
execution_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat(sprintf("⏱️ 실행 시간: %.2f초\n", execution_time))

# 결과 출력
cat("\n" , rep("=", 50), "\n")
cat("🎯 최종 함수 테스트 결과\n")
cat(rep("=", 50), "\n")

cat("\n▶️ 분석 결과:\n")
cat("  - 8대 감정 점수:\n")
emotion_scores <- result %>% select(기쁨, 슬픔, 분노, 혐오, 공포, 놀람, `애정/사랑`, 중립)
print(emotion_scores)

cat("\n  - PAD 모델 점수:\n")
pad_scores <- result %>% select(P, A, D)
print(pad_scores)

cat(sprintf("\n  - 지배 감정: %s\n", result$dominant_emotion))
cat(sprintf("  - 복합 감정 (PAD): %s\n", result$PAD_complex_emotion))

cat("\n  - 분석 근거:\n")
cat("   ", result$rationale, "\n")

if (!is.na(result$error_message)) {
  cat(sprintf("\n⚠️ 오류: %s\n", result$error_message))
} else {
  cat("\n✅ 성공적으로 분석 완료!\n")
}

cat("\n" , rep("=", 50), "\n")