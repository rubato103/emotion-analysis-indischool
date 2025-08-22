# gemini.R 패키지 버그 수정 테스트
# 개발자가 수정했다고 하니 원래 패키지로 테스트

cat("🧪 gemini.R 패키지 버그 수정 테스트 시작...\n\n")

# 1. 패키지 최신 버전 설치
cat("📦 gemini.R 패키지 최신 버전 설치...\n")
tryCatch({
  # 기존 버전 제거 후 최신 버전 설치
  if ("gemini.R" %in% installed.packages()[,"Package"]) {
    remove.packages("gemini.R")
    cat("  기존 gemini.R 패키지 제거 완료\n")
  }
  
  # 최신 버전 설치 (GitHub에서)
  if (!require(devtools, quietly = TRUE)) {
    install.packages("devtools")
  }
  
  devtools::install_github("jhk0530/gemini.R", force = TRUE)
  cat("  ✅ 최신 gemini.R 패키지 설치 완료\n")
  
}, error = function(e) {
  cat("  ⚠️ GitHub 설치 실패, CRAN에서 설치 시도...\n")
  install.packages("gemini.R", force = TRUE)
})

# 2. 패키지 로드 및 버전 확인
cat("\n📋 패키지 정보 확인...\n")
library(gemini.R)
package_info <- packageDescription("gemini.R")
cat(sprintf("  버전: %s\n", package_info$Version))
cat(sprintf("  날짜: %s\n", package_info$Date))

# 3. API 키 설정
cat("\n🔑 API 키 설정...\n")
api_key <- Sys.getenv("GEMINI_API_KEY")
if (api_key == "") {
  cat("  ❌ GEMINI_API_KEY 환경변수가 설정되지 않았습니다.\n")
  stop("API 키를 먼저 설정하세요.")
}

tryCatch({
  setAPI(api_key)
  cat("  ✅ API 키 설정 완료\n")
}, error = function(e) {
  cat(sprintf("  ❌ API 키 설정 실패: %s\n", e$message))
  stop("API 키 설정 실패")
})

# 4. 모델 목록 확인 (가능한 경우)
cat("\n📊 사용 가능한 모델 확인...\n")
tryCatch({
  # 일부 gemini.R 버전에서 지원하는 경우
  if (exists("listModels")) {
    models <- listModels()
    cat("  사용 가능한 모델:\n")
    for (i in 1:min(5, length(models))) {
      cat(sprintf("    %d. %s\n", i, models[i]))
    }
  } else {
    cat("  listModels 함수 없음 - 기본 모델로 테스트\n")
  }
}, error = function(e) {
  cat(sprintf("  ⚠️ 모델 목록 확인 실패: %s\n", e$message))
})

# 5. 기본 테스트 (간단한 텍스트)
cat("\n🧪 기본 API 호출 테스트...\n")

test_models <- c(
  "-1.5-flash",
  "-1.5-pro", 
  "-2.0-flash-exp",
  "-2.5-flash",
  "-2.5pro"
)

successful_model <- NULL

for (model in test_models) {
  cat(sprintf("  모델 테스트: %s\n", model))
  
  tryCatch({
    response <- gemini(
      prompt = "안녕하세요. 'OK'라고 답변해주세요.",
      model = model,
      temperature = 0.5,
      maxOutputTokens = 50
    )
    
    cat(sprintf("    ✅ 성공: %s\n", substr(response, 1, 50)))
    successful_model <- model
    break
    
  }, error = function(e) {
    cat(sprintf("    ❌ 실패: %s\n", e$message))
  })
  
  Sys.sleep(2)  # API 제한 방지
}

if (is.null(successful_model)) {
  cat("\n❌ 모든 모델 테스트 실패\n")
  cat("여전히 문제가 있는 것 같습니다.\n")
  stop("gemini.R 패키지 여전히 작동하지 않음")
}

# 6. 감정분석 테스트 (실제 사용 케이스)
cat(sprintf("\n🎯 감정분석 테스트 (모델: %s)...\n", successful_model))

emotion_prompt <- '다음 텍스트의 감정을 분석해주세요:
"오늘 정말 힘든 하루였어요. 아이들이 말을 안 들어서 너무 스트레스 받았습니다."

다음 JSON 형식으로 답변해주세요:
{
  "dominant_emotion": "주요 감정",
  "rationale": "분석 근거"
}'

tryCatch({
  emotion_response <- gemini(
    prompt = emotion_prompt,
    model = successful_model,
    temperature = 0.3,
    maxOutputTokens = 500
  )
  
  cat("  ✅ 감정분석 테스트 성공!\n")
  cat("  응답 내용:\n")
  cat(paste0("    ", emotion_response), "\n")
  
  # JSON 파싱 테스트
  tryCatch({
    clean_response <- gsub("```json\\s*|\\s*```", "", emotion_response)
    parsed <- jsonlite::fromJSON(clean_response)
    cat("  ✅ JSON 파싱 성공\n")
    cat(sprintf("    주요 감정: %s\n", parsed$dominant_emotion))
    
  }, error = function(e) {
    cat(sprintf("  ⚠️ JSON 파싱 실패: %s\n", e$message))
  })
  
}, error = function(e) {
  cat(sprintf("  ❌ 감정분석 테스트 실패: %s\n", e$message))
})

# 7. 최종 판정 및 권장사항
cat("\n", rep("=", 50), "\n")
cat("🎯 최종 테스트 결과:\n")

if (!is.null(successful_model)) {
  cat(sprintf("✅ gemini.R 패키지 정상 작동 확인!\n"))
  cat(sprintf("✅ 권장 모델: %s\n", successful_model))
  cat("\n🔄 기존 시스템을 gemini.R 패키지로 되돌릴까요?\n")
  cat("장점:\n")
  cat("  - 원래 설계된 방식으로 사용\n")
  cat("  - 더 간단한 코드\n")
  cat("  - 패키지 공식 지원\n")
  cat("\n현재 사용 중인 OpenAI 호환 엔드포인트:\n")
  cat("  - 안정적으로 작동 중\n")
  cat("  - 이미 검증됨\n")
  cat("  - 변경 위험 없음\n")
  
} else {
  cat("❌ gemini.R 패키지 여전히 문제 있음\n")
  cat("현재 OpenAI 호환 엔드포인트 유지 권장\n")
}

cat("\n", rep("=", 50), "\n")