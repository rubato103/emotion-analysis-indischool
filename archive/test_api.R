# Gemini API 테스트 스크립트
# OpenAI 호환 엔드포인트 직접 테스트

library(httr2)

# API 키 확인
api_key <- Sys.getenv("GEMINI_API_KEY")
if (api_key == "") {
  stop("GEMINI_API_KEY가 설정되지 않았습니다.")
}

cat("API 키 확인:", substr(api_key, nchar(api_key)-3, nchar(api_key)), "\n")

# 1. 사용 가능한 모델 목록 확인
cat("\n=== 사용 가능한 모델 목록 확인 ===\n")
models_url <- "https://generativelanguage.googleapis.com/v1beta/models"

tryCatch({
  models_resp <- request(models_url) %>%
    req_url_query(key = api_key) %>%
    req_perform()
  
  if (resp_status(models_resp) == 200) {
    models_data <- resp_body_json(models_resp)
    cat("사용 가능한 모델:\n")
    for (model in models_data$models[1:10]) {  # 처음 10개만 표시
      if (!is.null(model$name)) {
        model_name <- gsub("models/", "", model$name)
        cat(sprintf("  - %s\n", model_name))
      }
    }
  } else {
    cat("모델 목록 가져오기 실패:", resp_status(models_resp), "\n")
  }
}, error = function(e) {
  cat("모델 목록 요청 오류:", e$message, "\n")
})

# 2. OpenAI 호환 엔드포인트 테스트
cat("\n=== OpenAI 호환 엔드포인트 테스트 ===\n")

# 테스트할 모델들
test_models <- c(
  "gemini-2.0-flash-exp",
  "gemini-2.5-flash", 
  "gemini-2.0-flash",
  "gemini-1.5-flash",
  "gemini-1.5-pro"
)

openai_url <- "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"

for (model in test_models) {
  cat(sprintf("\n테스트 중: %s\n", model))
  
  request_body <- list(
    model = model,
    messages = list(list(role = "user", content = "Hello, respond with 'OK' if you can hear me.")),
    temperature = 0.5,
    max_tokens = 50,
    top_p = 0.9
  )
  
  tryCatch({
    resp <- request(openai_url) %>%
      req_headers(
        Authorization = paste("Bearer", api_key),
        `Content-Type` = "application/json"
      ) %>%
      req_body_json(request_body) %>%
      req_timeout(30) %>%
      req_perform()
    
    if (resp_status(resp) == 200) {
      result <- resp_body_json(resp)
      response_text <- result$choices[[1]]$message$content
      cat(sprintf("  ✅ 성공: %s\n", substring(response_text, 1, 50)))
      break  # 성공한 모델을 찾으면 중단
    } else {
      cat(sprintf("  ❌ 실패: HTTP %d\n", resp_status(resp)))
      error_body <- resp_body_string(resp)
      if (nchar(error_body) > 0) {
        cat(sprintf("     오류 내용: %s\n", substring(error_body, 1, 100)))
      }
    }
    
  }, error = function(e) {
    cat(sprintf("  ❌ 요청 오류: %s\n", e$message))
  })
  
  Sys.sleep(1)  # API 제한 방지
}

cat("\n=== 테스트 완료 ===\n")