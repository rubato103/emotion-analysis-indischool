# gemini.R 패키지용 새로운 함수들

# 0. gemini.R 패키지를 사용한 구조화된 API 호출 함수 (새 버전)
gemini_structured_call_new <- function(prompt, model = API_CONFIG$model_name, 
                                      temperature = API_CONFIG$temperature, 
                                      max_tokens = 8192, top_p = API_CONFIG$top_p) {
  
  api_key <- Sys.getenv("GEMINI_API_KEY")
  if (api_key == "") {
    stop("GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
  }
  
  # 감정분석용 JSON 스키마 정의
  emotion_schema <- list(
    type = "OBJECT",
    properties = list(
      emotion_scores = list(
        type = "OBJECT",
        properties = list(
          "기쁨" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "슬픔" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "분노" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "혐오" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "공포" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "놀람" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "애정/사랑" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "중립" = list(type = "NUMBER", minimum = 0, maximum = 1)
        ),
        required = c("기쁨", "슬픔", "분노", "혐오", "공포", "놀람", "애정/사랑", "중립")
      ),
      PAD = list(
        type = "OBJECT",
        properties = list(
          P = list(type = "NUMBER", minimum = -1, maximum = 1),
          A = list(type = "NUMBER", minimum = -1, maximum = 1),
          D = list(type = "NUMBER", minimum = -1, maximum = 1)
        ),
        required = c("P", "A", "D")
      ),
      PAD_complex_emotion = list(type = "STRING"),
      dominant_emotion = list(type = "STRING"),
      rationale = list(type = "STRING")
    ),
    required = c("emotion_scores", "PAD", "PAD_complex_emotion", "dominant_emotion", "rationale")
  )
  
  tryCatch({
    # gemini_structured 사용
    response <- gemini_structured(
      prompt = prompt,
      schema = emotion_schema,
      model = model,
      temperature = temperature,
      maxOutputTokens = max_tokens,
      topP = top_p
    )
    
    # 디버깅: 원본 응답 확인
    cat("🔍 디버그: 원본 응답:\n")
    cat(response, "\n\n")
    
    # JSON 파싱
    response_clean <- gsub("```json\\s*|\\s*```", "", response, perl = TRUE)
    response_clean <- gsub("^\\s+|\\s+$", "", response_clean)
    response_clean <- gsub("[\\x00-\\x1F\\x7F-\\x9F]", "", response_clean)
    response_clean <- gsub("\\ufffd", "", response_clean)
    
    # 한글 단어 사이 공백 수정 (더 포괄적으로)
    response_clean <- gsub("([가-힣])\\s+([가-힣])", "\\1\\2", response_clean)
    
    response_clean <- iconv(response_clean, to = "UTF-8", sub = "")
    
    cat("🔍 디버그: 정리된 JSON:\n")
    cat(response_clean, "\n\n")
    
    parsed_data <- jsonlite::fromJSON(response_clean, flatten = TRUE)
    
    return(parsed_data)
    
  }, error = function(e) {
    stop(paste("gemini structured API 호출 실패:", e$message))
  })
}

# 1. 새로운 감정분석 함수 (gemini.R 패키지 전용)
analyze_emotion_gemini_structured <- function(prompt_text,
                                            model_to_use = API_CONFIG$model_name,
                                            temp_to_use = API_CONFIG$temperature,
                                            top_p_to_use = API_CONFIG$top_p,
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
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  
  # 재시도 로직
  for (attempt in 1:max_retries) {
    tryCatch({
      # gemini_structured 사용
      parsed_data <- gemini_structured_call_new(
        prompt = prompt_text,
        model = model_to_use,
        temperature = temp_to_use,
        top_p = top_p_to_use
      )
      
      # 데이터 추출 및 검증
      if (all(c("emotion_scores", "PAD", "dominant_emotion", "rationale") %in% names(parsed_data))) {
        
        emotion_scores <- parsed_data$emotion_scores
        pad_scores <- parsed_data$PAD
        
        # 출력 데이터프레임 업데이트
        output_df$기쁨 <- as.numeric(emotion_scores[["기쁨"]])
        output_df$슬픔 <- as.numeric(emotion_scores[["슬픔"]])
        output_df$분노 <- as.numeric(emotion_scores[["분노"]])
        output_df$혐오 <- as.numeric(emotion_scores[["혐오"]])
        output_df$공포 <- as.numeric(emotion_scores[["공포"]])
        output_df$놀람 <- as.numeric(emotion_scores[["놀람"]])
        output_df$`애정/사랑` <- as.numeric(emotion_scores[["애정/사랑"]])
        output_df$중립 <- as.numeric(emotion_scores[["중립"]])
        
        output_df$P <- as.numeric(pad_scores[["P"]])
        output_df$A <- as.numeric(pad_scores[["A"]])
        output_df$D <- as.numeric(pad_scores[["D"]])
        
        output_df$PAD_complex_emotion <- as.character(parsed_data$PAD_complex_emotion)
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