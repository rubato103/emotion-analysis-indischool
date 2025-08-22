# gemini.R 패키지 디버깅 스크립트

# 설정 로드
source("config.R")

# 패키지 로드
library(dplyr)
library(jsonlite)

# gemini.R 패키지 확인
if (!require("gemini.R", quietly = TRUE)) {
  stop("gemini.R 패키지가 설치되지 않았습니다.")
}

# API 키 확인
if (Sys.getenv("GEMINI_API_KEY") == "") { 
  stop("⚠️ Gemini API 키가 설정되지 않았습니다.") 
}

cat("✅ 환경 설정 완료\n\n")

# 1단계: 간단한 테스트 스키마
cat("=== 1단계: 간단한 스키마 테스트 ===\n")
simple_schema <- list(
  type = "OBJECT",
  properties = list(
    message = list(type = "STRING"),
    number = list(type = "NUMBER", minimum = 0, maximum = 10)
  ),
  required = c("message", "number")
)

simple_prompt <- "간단한 메시지와 1-10 사이의 숫자를 반환해주세요."

cat("스키마:\n")
str(simple_schema)

cat("\n프롬프트:", simple_prompt, "\n")

tryCatch({
  simple_result <- gemini_structured(
    prompt = simple_prompt,
    schema = simple_schema,
    model = API_CONFIG$model_name,
    temperature = 0.2,
    topP = 0.8
  )
  
  cat("\n🔍 간단한 테스트 결과 타입:", class(simple_result), "\n")
  cat("🔍 간단한 테스트 결과 구조:\n")
  str(simple_result)
  cat("\n🔍 간단한 테스트 결과 내용:\n")
  print(simple_result)
  
}, error = function(e) {
  cat("❌ 간단한 테스트 실패:", e$message, "\n")
})

cat("\n" , rep("=", 60), "\n")

# 2단계: 감정분석 스키마 테스트
cat("=== 2단계: 감정분석 스키마 테스트 ===\n")

emotion_schema <- list(
  type = "OBJECT",
  properties = list(
    emotion_scores = list(
      type = "OBJECT",
      properties = list(
        "기쁨" = list(type = "NUMBER", minimum = 0, maximum = 1),
        "슬픔" = list(type = "NUMBER", minimum = 0, maximum = 1),
        "분노" = list(type = "NUMBER", minimum = 0, maximum = 1),
        "중립" = list(type = "NUMBER", minimum = 0, maximum = 1)
      ),
      required = c("기쁨", "슬픔", "분노", "중립")
    ),
    dominant_emotion = list(type = "STRING"),
    rationale = list(type = "STRING")
  ),
  required = c("emotion_scores", "dominant_emotion", "rationale")
)

emotion_prompt <- "다음 텍스트의 감정을 분석해주세요: '오늘 정말 좋은 하루였다!'"

cat("감정분석 스키마:\n")
str(emotion_schema)

cat("\n감정분석 프롬프트:", emotion_prompt, "\n")

tryCatch({
  emotion_result <- gemini_structured(
    prompt = emotion_prompt,
    schema = emotion_schema,
    model = API_CONFIG$model_name,
    temperature = 0.2,
    topP = 0.8
  )
  
  cat("\n🔍 감정분석 결과 타입:", class(emotion_result), "\n")
  cat("🔍 감정분석 결과 구조:\n")
  str(emotion_result)
  cat("\n🔍 감정분석 결과 내용:\n")
  print(emotion_result)
  
  # JSON 문자열인 경우 파싱 시도
  if (is.character(emotion_result)) {
    cat("\n🔄 JSON 파싱 시도...\n")
    
    # 기본 정리
    cleaned <- gsub("```json\\s*|\\s*```", "", emotion_result, perl = TRUE)
    cleaned <- gsub("^\\s+|\\s+$", "", cleaned)
    
    cat("정리된 JSON:\n")
    cat(cleaned, "\n")
    
    parsed <- jsonlite::fromJSON(cleaned, flatten = TRUE)
    cat("\n🔍 파싱된 결과 구조:\n")
    str(parsed)
    cat("\n🔍 파싱된 결과 내용:\n")
    print(parsed)
  }
  
}, error = function(e) {
  cat("❌ 감정분석 테스트 실패:", e$message, "\n")
})

cat("\n" , rep("=", 60), "\n")
cat("🏁 디버깅 완료\n")