# 선택한 모델로 배치 API 테스트
# 목적: gemini-2.5-flash-lite-preview-06-17 모델 배치 처리 확인

source("config.R")
library(httr2)
library(jsonlite)

api_key <- Sys.getenv("GEMINI_API_KEY")
selected_model <- BATCH_CONFIG$model_name

cat(sprintf("=== %s 모델 배치 테스트 ===\n", selected_model))

# 배치 요청 생성
batch_request <- list(
  batch = list(
    display_name = sprintf("test_%s", gsub("[^a-zA-Z0-9]", "_", selected_model)),
    input_config = list(
      requests = list(
        requests = list(
          list(
            request = list(
              contents = list(
                list(
                  parts = list(
                    list(text = "이 텍스트의 감정을 분석해주세요: '오늘 정말 기뻤어요!'")
                  )
                )
              ),
              generationConfig = list(
                temperature = BATCH_CONFIG$temperature,
                topP = BATCH_CONFIG$top_p
              )
            ),
            metadata = list(key = "emotion-test-1")
          )
        )
      )
    )
  )
)

cat("🔍 선택한 모델:", selected_model, "\n")
cat("🔍 배치 설정:\n")
cat(sprintf("  - Temperature: %.1f\n", BATCH_CONFIG$temperature))
cat(sprintf("  - Top-P: %.1f\n", BATCH_CONFIG$top_p))

tryCatch({
  # 5분 대기 (이전 429 오류 방지)
  cat("⏳ API 제한 해제를 위해 잠시 대기 중...\n")
  Sys.sleep(10)  # 10초만 대기 (테스트용)
  
  response <- httr2::request(sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:batchGenerateContent", selected_model)) %>%
    httr2::req_headers(
      `x-goog-api-key` = api_key,
      `Content-Type` = "application/json"
    ) %>%
    httr2::req_body_json(batch_request) %>%
    httr2::req_perform()
  
  batch_result <- httr2::resp_body_json(response)
  
  cat("✅ 배치 작업 생성 성공!\n")
  cat(sprintf("📋 작업 이름: %s\n", batch_result$name))
  
  # 상태 확인
  cat("\n⏳ 배치 상태 확인 중...\n")
  Sys.sleep(3)
  
  status_response <- httr2::request(sprintf("https://generativelanguage.googleapis.com/v1beta/%s", batch_result$name)) %>%
    httr2::req_headers(`x-goog-api-key` = api_key) %>%
    httr2::req_perform()
  
  status_result <- httr2::resp_body_json(status_response)
  cat(sprintf("현재 상태: %s\n", status_result$metadata$state))
  
  cat("\n🎉 선택한 모델로 배치 처리 테스트 성공!\n")
  cat("\n📋 다음 단계:\n")
  cat("1. 실제 감정분석 배치 처리 시작:\n")
  cat('   source("04_배치처리_감정분석.R")\n')
  cat('   result <- run_batch_emotion_analysis("pilot")\n\n')
  
  cat("2. 배치 모니터링:\n")
  cat('   source("batch_monitor.R")\n')
  cat('   interactive_batch_manager()\n\n')
  
  cat(sprintf("3. 이 테스트 배치 상태 계속 확인: %s\n", batch_result$name))
  
}, error = function(e) {
  cat(sprintf("❌ 배치 테스트 실패: %s\n", e$message))
  
  if (exists("response")) {
    tryCatch({
      error_content <- httr2::resp_body_string(response)
      cat("❌ 오료 상세:\n")
      cat(error_content, "\n")
      
      error_json <- jsonlite::fromJSON(error_content)
      if (!is.null(error_json$error)) {
        if (grepl("429", error_json$error$code)) {
          cat("\n💡 다시 429 오류가 발생했습니다.\n")
          cat("   더 오래 대기한 후 다시 시도하세요 (10-15분)\n")
          cat("   또는 나중에 04_배치처리_감정분석.R을 직접 실행하세요\n")
        }
      }
    }, error = function(e2) {})
  }
})

cat("\n=== 테스트 완료 ===\n")