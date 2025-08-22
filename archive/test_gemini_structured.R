# gemini.R 패키지 전용 테스트 스크립트

# 설정 및 함수 로드
source("config.R")
source("utils.R") 
source("functions_gemini_structured.R")

# 패키지 로드
library(dplyr)
library(jsonlite)

# gemini.R 패키지 확인
if (!require("gemini.R", quietly = TRUE)) {
  stop("gemini.R 패키지가 설치되지 않았습니다.")
}

cat("✅ gemini.R 패키지 로드 완료\n")

# API 키 확인
if (Sys.getenv("GEMINI_API_KEY") == "") { 
  stop("⚠️ Gemini API 키가 설정되지 않았습니다.") 
}

cat("✅ API 키 확인 완료\n")

# 테스트 텍스트
test_text <- "그래도 학교생활의 추억을 만드는 것도 교사가 해야 할..."

# 프롬프트 생성 (간단한 버전)
test_prompt <- paste0(
  "## 역할: 고도로 훈련된 리서치 보조원\n",
  "## 컨텍스트: 모든 텍스트는 직업인증이 필요한 초등교사 커뮤니티에서 수집됨.\n",
  "## 지시:\n",
  "1. **감정 점수 (0.00~1.00)**: 8개 감정(기쁨, 슬픔, 분노, 혐오, 공포, 놀람, 애정/사랑, 중립) 평가.\n",
  "2. **PAD 모델 점수 (-1.00~1.00)**: P(쾌락/긍정성), A(각성/활성도), D(지배/통제감) 평가.\n",
  "3. **결과 명명**: PAD 점수 기반 \"복합 감정\" 명명 및 최고점 감정을 \"지배 감정\"으로 선정.\n",
  "4. **분석 근거 제시**: 모든 평가 점수 및 결과에 대한 논리적 근거를 서술.\n\n",
  "## 분석 과업: 다음 '게시글'의 감정을 분석.\n\n",
  "# 분석할 게시글 (분석 대상)\n", test_text
)

cat("📝 테스트 시작...\n")
start_time <- Sys.time()

# 새로운 함수로 분석
result <- analyze_emotion_gemini_structured(
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
cat("🎯 새로운 gemini_structured 테스트 결과\n")
cat(rep("=", 50), "\n")

cat("\n▶️ 분석 대상:\n")
cat("  ", test_text, "\n\n")

cat("▶️ 분석 결과:\n")
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
}

cat("\n" , rep("=", 50), "\n")
cat("✅ 테스트 완료\n")