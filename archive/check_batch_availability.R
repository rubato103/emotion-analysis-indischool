# Gemini 배치 API 사용 가능 여부 확인
# 목적: 배치 기능이 활성화되어 있는지 사전 확인

library(httr2)
library(jsonlite)

api_key <- Sys.getenv("GEMINI_API_KEY")
if (api_key == "") {
  stop("⚠️ GEMINI_API_KEY가 설정되지 않았습니다.")
}

cat("=== Gemini 배치 API 사용 가능성 확인 ===\n\n")

# 1. 지원되는 모델 목록 확인
cat("1. 지원되는 모델 목록 확인...\n")

tryCatch({
  models_response <- httr2::request("https://generativelanguage.googleapis.com/v1beta/models") %>%
    httr2::req_headers(`x-goog-api-key` = api_key) %>%
    httr2::req_perform()
  
  models_result <- httr2::resp_body_json(models_response)
  
  # 배치 지원 모델 찾기
  batch_models <- c()
  for (model in models_result$models) {
    model_name <- model$name
    if (!is.null(model$supportedGenerationMethods)) {
      if ("batchGenerateContent" %in% model$supportedGenerationMethods) {
        batch_models <- c(batch_models, model_name)
      }
    }
  }
  
  if (length(batch_models) > 0) {
    cat("✅ 배치 지원 모델 발견:\n")
    for (model in batch_models) {
      cat(sprintf("   - %s\n", model))
    }
  } else {
    cat("❌ 배치를 지원하는 모델을 찾을 수 없습니다.\n")
    cat("💡 가능한 원인:\n")
    cat("   - 배치 API가 아직 계정에 활성화되지 않음\n")
    cat("   - 지역 제한\n")
    cat("   - API 키 권한 부족\n")
  }
  
}, error = function(e) {
  cat(sprintf("❌ 모델 목록 조회 실패: %s\n", e$message))
})

# 2. 배치 작업 목록 조회 시도 (권한 확인용)
cat("\n2. 배치 작업 목록 조회 시도...\n")

tryCatch({
  batches_response <- httr2::request("https://generativelanguage.googleapis.com/v1beta/batches") %>%
    httr2::req_headers(`x-goog-api-key` = api_key) %>%
    httr2::req_perform()
  
  batches_result <- httr2::resp_body_json(batches_response)
  
  cat("✅ 배치 목록 조회 성공! 배치 API 접근 가능합니다.\n")
  
  if (!is.null(batches_result$batches) && length(batches_result$batches) > 0) {
    cat(sprintf("📋 기존 배치 작업: %d개\n", length(batches_result$batches)))
  } else {
    cat("📋 기존 배치 작업 없음 (정상)\n")
  }
  
}, error = function(e) {
  cat(sprintf("❌ 배치 목록 조회 실패: %s\n", e$message))
  
  if (exists("batches_response")) {
    tryCatch({
      error_content <- httr2::resp_body_string(batches_response)
      error_json <- jsonlite::fromJSON(error_content)
      
      if (!is.null(error_json$error)) {
        cat(sprintf("에러 코드: %s\n", error_json$error$code))
        
        if (error_json$error$code == 403) {
          cat("💡 권한 문제일 가능성이 높습니다.\n")
          cat("   - Google Cloud Console에서 Generative Language API 활성화 확인\n")
          cat("   - API 키에 배치 권한이 있는지 확인\n")
        } else if (error_json$error$code == 404) {
          cat("💡 배치 API가 활성화되지 않았을 수 있습니다.\n")
        }
      }
    }, error = function(e2) {})
  }
})

# 3. 일반 API 작동 확인 (비교용)
cat("\n3. 일반 generateContent API 확인...\n")

tryCatch({
  normal_request <- list(
    contents = list(
      list(
        parts = list(
          list(text = "Test")
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
  
  cat("✅ 일반 API 정상 작동\n")
  
}, error = function(e) {
  cat(sprintf("❌ 일반 API도 실패: %s\n", e$message))
  cat("💡 API 키 자체에 문제가 있을 수 있습니다.\n")
})

# 4. 결론 및 권장사항
cat("\n=== 결론 및 권장사항 ===\n")

cat("💭 배치 API 사용 가능 여부:\n")
cat("   위의 테스트 결과를 확인하세요.\n\n")

cat("🚀 다음 단계:\n")
cat("1. 모든 테스트가 성공했다면:\n")
cat('   source("simple_batch_test.R")  # 실제 배치 테스트\n\n')

cat("2. 일부 실패했다면:\n")
cat("   - Google Cloud Console에서 Generative Language API 활성화\n")
cat("   - 배치 기능이 지원되는 지역인지 확인\n")
cat("   - API 키 권한 재확인\n\n")

cat("3. 배치가 사용 불가능하다면:\n")
cat("   - 기존 03_감정분석_전체실행_v2.R 사용 (실시간 처리)\n")
cat("   - 배치 기능이 활성화될 때까지 대기\n\n")

cat("📞 추가 지원이 필요하면 Google Cloud 지원팀에 문의하세요.\n")

cat("\n=== 확인 완료 ===\n")