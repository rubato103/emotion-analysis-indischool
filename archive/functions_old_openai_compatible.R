# 기존 OpenAI 호환 엔드포인트 기반 함수들 - 아카이브됨 (2025-07-23)
# gemini.R 패키지로 대체됨

# 0. 개선된 gemini API 함수 (OpenAI 호환 엔드포인트 사용)
gemini_openai_compatible <- function(prompt, model = "gemini-2.0-flash", temperature = 1, 
                                   maxOutputTokens = 8192, topP = 0.95, timeout = 60) {
  
  api_key <- Sys.getenv("GEMINI_API_KEY")
  if (api_key == "") {
    stop("GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
  }
  
  # OpenAI 호환 엔드포인트 사용
  url <- "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
  
  request_body <- list(
    model = model,
    messages = list(list(role = "user", content = prompt)),
    temperature = temperature,
    max_tokens = maxOutputTokens,
    top_p = topP
  )
  
  tryCatch({
    req <- httr2::request(url) %>%
      httr2::req_headers(
        Authorization = paste("Bearer", api_key),
        `Content-Type` = "application/json"
      ) %>%
      httr2::req_body_json(request_body) %>%
      httr2::req_timeout(timeout)
    
    resp <- httr2::req_perform(req)
    
    if (httr2::resp_status(resp) == 200) {
      result <- httr2::resp_body_json(resp)
      return(result$choices[[1]]$message$content)
    } else {
      stop(paste("API Error:", httr2::resp_status(resp), httr2::resp_body_string(resp)))
    }
    
  }, error = function(e) {
    stop(paste("gemini API 호출 실패:", e$message))
  })
}

# 감정분석 API 호출 함수 (아카이브)
analyze_emotion_robust_old <- function(prompt_text,
                                   model_to_use,
                                   temp_to_use,
                                   top_p_to_use,
                                   max_retries = 5) {
  
  # 출력 구조 정의
  output_df <- data.frame(
    기쁨 = NA_real_, 슬픔 = NA_real_, 분노 = NA_real_, 혐오 = NA_real_,
    공포 = NA_real_, 놀람 = NA_real_, `애정/사랑` = NA_real_, 중립 = NA_real_,
    P = NA_real_, A = NA_real_, D = NA_real_,
    PAD_complex_emotion = NA_character_,
    dominant_emotion = NA_character_,
    rationale = NA_character_,
    unexpected_emotions = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE
  )
  
  # 재시도 로직
  for (attempt in 1:max_retries) {
    tryCatch({
      # API 호출 (개선된 OpenAI 호환 엔드포인트 사용)
      response <- gemini_openai_compatible(
        prompt = prompt_text,
        model = model_to_use,
        temperature = temp_to_use,
        topP = top_p_to_use
      )
      
      # JSON 파싱
      response_clean <- gsub("```json\\s*|\\s*```", "", response, perl = TRUE)
      response_clean <- gsub("^\\s+|\\s+$", "", response_clean)
      
      parsed_data <- fromJSON(response_clean, flatten = TRUE)
      
      # 데이터 추출 및 검증
      if (all(c("emotion_scores", "PAD", "dominant_emotion", "rationale") %in% names(parsed_data))) {
        
        emotion_scores <- parsed_data$emotion_scores
        pad_scores <- parsed_data$PAD
        
        # 출력 데이터프레임 업데이트
        if (length(emotion_scores) >= 8) {
          output_df$기쁨 <- as.numeric(emotion_scores[[1]])
          output_df$슬픔 <- as.numeric(emotion_scores[[2]])
          output_df$분노 <- as.numeric(emotion_scores[[3]])
          output_df$혐오 <- as.numeric(emotion_scores[[4]])
          output_df$공포 <- as.numeric(emotion_scores[[5]])
          output_df$놀람 <- as.numeric(emotion_scores[[6]])
          output_df$`애정/사랑` <- as.numeric(emotion_scores[[7]])
          output_df$중립 <- as.numeric(emotion_scores[[8]])
        }
        
        if (length(pad_scores) >= 3) {
          output_df$P <- as.numeric(pad_scores[[1]])
          output_df$A <- as.numeric(pad_scores[[2]])
          output_df$D <- as.numeric(pad_scores[[3]])
        }
        
        output_df$PAD_complex_emotion <- as.character(parsed_data$PAD_complex_emotion %||% NA)
        output_df$dominant_emotion <- as.character(parsed_data$dominant_emotion)
        output_df$rationale <- as.character(parsed_data$rationale)
        output_df$unexpected_emotions <- as.character(parsed_data$unexpected_emotions %||% NA)
        
        return(output_df)
      }
      
    }, error = function(e) {
      cat(sprintf("시도 %d/%d 실패: %s\n", attempt, max_retries, e$message))
      if (attempt == max_retries) {
        output_df$dominant_emotion <- "API 오류"
        output_df$error_message <- paste("최대 재시도 후 실패:", e$message)
        return(output_df)
      }
      wait_time <- 2^attempt  # 지수 백오프
      cat(sprintf("%d초 대기 후 재시도...\n", wait_time))
      Sys.sleep(wait_time)
    })
  }
  
  return(output_df)
}