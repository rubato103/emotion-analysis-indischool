# 최종 수정된 감정분석 함수들

# 1. gemini.R 패키지 전용 감정분석 함수
analyze_emotion_final <- function(prompt_text,
                                 model_to_use = API_CONFIG$model_name,
                                 temp_to_use = API_CONFIG$temperature,
                                 top_p_to_use = API_CONFIG$top_p,
                                 max_retries = 5) {
  
  # gemini.R 패키지 확인
  if (!require("gemini.R", quietly = TRUE)) {
    stop("gemini.R 패키지가 설치되지 않았습니다.")
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
      # gemini_structured 호출
      response <- gemini_structured(
        prompt = prompt_text,
        schema = emotion_schema,
        model = model_to_use,
        temperature = temp_to_use,
        topP = top_p_to_use
      )
      
      # gemini_structured 응답 정리 (가끔 ```json이 포함될 수 있음)
      response_clean <- gsub("```json\\s*|\\s*```", "", response, perl = TRUE)
      response_clean <- gsub("^\\s+|\\s+$", "", response_clean)
      
      parsed_data <- jsonlite::fromJSON(response_clean, flatten = TRUE)
      
      # 데이터 추출 및 검증
      if (all(c("emotion_scores", "PAD", "dominant_emotion", "rationale") %in% names(parsed_data))) {
        
        emotion_scores <- parsed_data$emotion_scores
        pad_scores <- parsed_data$PAD
        
        # 안전한 데이터 추출 (NULL 체크 포함)
        output_df$기쁨 <- as.numeric(emotion_scores[["기쁨"]] %||% NA_real_)
        output_df$슬픔 <- as.numeric(emotion_scores[["슬픔"]] %||% NA_real_)
        output_df$분노 <- as.numeric(emotion_scores[["분노"]] %||% NA_real_)
        output_df$혐오 <- as.numeric(emotion_scores[["혐오"]] %||% NA_real_)
        output_df$공포 <- as.numeric(emotion_scores[["공포"]] %||% NA_real_)
        output_df$놀람 <- as.numeric(emotion_scores[["놀람"]] %||% NA_real_)
        output_df$`애정/사랑` <- as.numeric(emotion_scores[["애정/사랑"]] %||% NA_real_)
        output_df$중립 <- as.numeric(emotion_scores[["중립"]] %||% NA_real_)
        
        output_df$P <- as.numeric(pad_scores[["P"]] %||% NA_real_)
        output_df$A <- as.numeric(pad_scores[["A"]] %||% NA_real_)
        output_df$D <- as.numeric(pad_scores[["D"]] %||% NA_real_)
        
        output_df$PAD_complex_emotion <- as.character(parsed_data$PAD_complex_emotion %||% NA_character_)
        output_df$dominant_emotion <- as.character(parsed_data$dominant_emotion %||% NA_character_)
        output_df$rationale <- as.character(parsed_data$rationale %||% NA_character_)
        output_df$unexpected_emotions <- as.character(parsed_data$unexpected_emotions %||% NA_character_)
        
        return(output_df)
      } else {
        stop("응답에 필수 필드가 없습니다")
      }
      
    }, error = function(e) {
      error_context <- substr(prompt_text, 1, 50)
      cat(sprintf("시도 %d/%d 실패 (입력: '%s...'): %s\n", attempt, max_retries, error_context, e$message))
      
      if (attempt == max_retries) {
        output_df$dominant_emotion <- "API 오류"
        output_df$error_message <- paste("최대 재시도 후 실패:", e$message)
        return(output_df)
      }
      wait_time <- 2^attempt
      cat(sprintf("%d초 대기 후 재시도...\n", wait_time))
      Sys.sleep(wait_time)
    })
  }
  
  return(output_df)
}

# 2. NULL coalescing operator (utils.R에 없는 경우 대비)
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) {
    y
  } else {
    x
  }
}