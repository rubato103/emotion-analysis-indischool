# 최소한의 배치 API 테스트
# 목적: 가장 기본적인 형태로 배치 API 연결 확인

# API 키 확인
api_key <- Sys.getenv("GEMINI_API_KEY")
if (api_key == "") {
  stop("⚠️ GEMINI_API_KEY가 설정되지 않았습니다.")
}

# 필요한 패키지
library(httr2, quietly = TRUE)
library(jsonlite, quietly = TRUE)

cat("=== 최소한의 배치 API 테스트 ===\n")

# 1. 먼저 일반 API가 작동하는지 확인
cat("1. 일반 generateContent API 테스트...\n")

tryCatch({
  normal_request <- list(
    contents = list(
      list(
        parts = list(
          list(text = "Hello")
        )
      )
    )
  )
  
  normal_response <- httr2::request("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent") %>%
    httr2::req_headers(
      `x-goog-api-key` = api_key,
      `Content-Type` = "application/json"
    ) %>%
    httr2::req_body_json(normal_request) %>%
    httr2::req_perform()
  
  normal_result <- httr2::resp_body_json(normal_response)
  cat("✅ 일반 API 작동 확인\n")
  
}, error = function(e) {
  cat(sprintf("❌ 일반 API 실패: %s\n", e$message))
  
  if (exists("normal_response")) {
    tryCatch({
      error_content <- httr2::resp_body_string(normal_response)
      cat("오류 내용:", error_content, "\n")
    }, error = function(e2) {})
  }
  
  stop("일반 API가 작동하지 않습니다. 배치 API 테스트를 중단합니다.")
})

# 2. 배치 API 기능 확인 - 가장 간단한 형태
cat("\n2. 배치 API 테스트...\n")

# Google 문서의 정확한 예시 형식
batch_request <- list(
  batch = list(
    display_name = "simple-test",
    input_config = list(
      requests = list(
        requests = list(
          list(
            request = list(
              contents = list(
                list(
                  parts = list(
                    list(text = "What is 2+2?")
                  )
                )
              )
            ),
            metadata = list(key = "test-1")
          )
        )
      )
    )
  )
)

cat("🔍 배치 요청 구조:\n")
cat(jsonlite::toJSON(batch_request, auto_unbox = TRUE, pretty = TRUE), "\n")

tryCatch({
  batch_response <- httr2::request("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:batchGenerateContent") %>%
    httr2::req_headers(
      `x-goog-api-key` = api_key,
      `Content-Type` = "application/json"
    ) %>%
    httr2::req_body_json(batch_request) %>%
    httr2::req_perform()
  
  batch_result <- httr2::resp_body_json(batch_response)
  
  cat("✅ 배치 API 테스트 성공!\n")
  cat(sprintf("배치 작업 이름: %s\n", batch_result$name))
  
  # 상태 확인
  cat("\n⏳ 배치 상태 확인...\n")
  Sys.sleep(2)
  
  status_response <- httr2::request(sprintf("https://generativelanguage.googleapis.com/v1beta/%s", batch_result$name)) %>%
    httr2::req_headers(`x-goog-api-key` = api_key) %>%
    httr2::req_perform()
  
  status_result <- httr2::resp_body_json(status_response)
  cat(sprintf("현재 상태: %s\n", status_result$metadata$state))
  
  cat("\n🎉 배치 API 연결 성공! 이제 감정분석 배치 처리를 시도할 수 있습니다.\n")
  
}, error = function(e) {
  cat(sprintf("❌ 배치 API 실패: %s\n", e$message))
  
  if (exists("batch_response")) {
    tryCatch({
      error_content <- httr2::resp_body_string(batch_response)
      cat("❌ 배치 API 오류 상세:\n")
      cat(error_content, "\n")
      
      # JSON 파싱 시도
      error_json <- jsonlite::fromJSON(error_content)
      if (!is.null(error_json$error)) {
        cat(sprintf("에러 코드: %s\n", error_json$error$code))
        cat(sprintf("에러 메시지: %s\n", error_json$error$message))
        
        # 가능한 해결책 제안
        if (grepl("404", error_json$error$code) || grepl("NOT_FOUND", error_json$error$message)) {
          cat("\n💡 해결책:\n")
          cat("- 배치 API가 아직 활성화되지 않았을 수 있습니다\n")
          cat("- 다른 모델명을 시도해보세요 (gemini-2.5-flash)\n")
          cat("- Google Cloud Console에서 배치 API 활성화 확인\n")
        } else if (grepl("400", error_json$error$code)) {
          cat("\n💡 해결책:\n")
          cat("- 요청 형식이 올바르지 않을 수 있습니다\n")
          cat("- API 키 권한을 확인하세요\n")
        }
      }
    }, error = function(e2) {
      cat("오류 내용을 파싱할 수 없습니다.\n")
    })
  }
})

cat("\n=== 테스트 완료 ===\n")