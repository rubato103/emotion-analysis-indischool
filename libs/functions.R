# 통합 함수 정의 파일
# 모든 필요한 함수들을 하나의 파일로 통합

# 필수 패키지 로드 확인
suppressMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
  if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
  if (!requireNamespace("gemini.R", quietly = TRUE)) install.packages("gemini.R")
  library(jsonlite, quietly = TRUE)
  library(dplyr, quietly = TRUE)
  library(gemini.R, quietly = TRUE)
})

# Null-coalescing operator 정의
`%||%` <- function(lhs, rhs) {
  if (!is.null(lhs) && length(lhs) > 0 && !is.na(lhs) && lhs != "") lhs else rhs
}

# 1. 프롬프트 생성 함수 (config.R의 PROMPT_CONFIG 사용)
create_analysis_prompt <- function(text, 구분, title = NULL, context = NULL, context_title = NULL, batch_mode = FALSE) {
  if (!exists("PROMPT_CONFIG")) stop("❌ PROMPT_CONFIG가 로드되지 않았습니다. config.R을 먼저 로드해주세요.")
  
  base_instructions <- PROMPT_CONFIG$base_instructions
  if (batch_mode) {
    base_instructions <- paste0(base_instructions, PROMPT_CONFIG$batch_json_instruction)
  }
  
  if (구분 == "댓글") {
    full_context <- if (!is.null(context_title) && !is.na(context_title)) paste(context_title, context, sep = "\n\n") else context
    final_prompt <- paste(base_instructions, PROMPT_CONFIG$comment_task, PROMPT_CONFIG$context_header, full_context, PROMPT_CONFIG$comment_header, text, sep = "\n\n")
  } else {
    full_text_post <- if (!is.null(title) && !is.na(title)) paste(title, text, sep = "\n\n") else text
    final_prompt <- paste(base_instructions, PROMPT_CONFIG$post_task, PROMPT_CONFIG$post_header, full_text_post, sep = "\n\n")
  }
  return(final_prompt)
}

# 2. 안정성을 높인 통합 JSON 파싱 함수
parse_emotion_response <- function(json_text) {
  # 항상 일관된 구조를 반환하기 위한 템플릿
  output_df <- data.frame(
    기쁨 = NA_real_, 신뢰 = NA_real_, 공포 = NA_real_, 놀람 = NA_real_,
    슬픔 = NA_real_, 혐오 = NA_real_, 분노 = NA_real_, 기대 = NA_real_,
    P = NA_real_, A = NA_real_, D = NA_real_,
    combinated_emotion = NA_character_,
    complex_emotion = NA_character_,
    rationale = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  
  tryCatch({
    if (is.null(json_text) || json_text == "") {
      stop("API 응답이 비어있습니다.")
    }
    
    response_clean <- gsub("```json[[:space:]]*|[[:space:]]*```", "", json_text, perl = TRUE)
    response_clean <- trimws(response_clean)
    
    if (nchar(response_clean) == 0) {
      stop("정리 후 내용이 비어있습니다.")
    }
    
    parsed_data <- jsonlite::fromJSON(response_clean, flatten = TRUE)
    
    # 필수 필드 존재 여부 확인
    required_fields <- c("plutchik_emotions", "PAD", "combinated_emotion", "complex_emotion", "rationale")
    if (!all(required_fields %in% names(parsed_data))) {
      stop("응답에 필수 필드가 누락되었습니다.")
    }
    
    plutchik <- parsed_data$plutchik_emotions
    pad <- parsed_data$PAD
    
    # 값 할당
    output_df$기쁨 <- as.numeric(plutchik[["기쁨"]] %||% NA_real_)
    output_df$신뢰 <- as.numeric(plutchik[["신뢰"]] %||% NA_real_)
    output_df$공포 <- as.numeric(plutchik[["공포"]] %||% NA_real_)
    output_df$놀람 <- as.numeric(plutchik[["놀람"]] %||% NA_real_)
    output_df$슬픔 <- as.numeric(plutchik[["슬픔"]] %||% NA_real_)
    output_df$혐오 <- as.numeric(plutchik[["혐오"]] %||% NA_real_)
    output_df$분노 <- as.numeric(plutchik[["분노"]] %||% NA_real_)
    output_df$기대 <- as.numeric(plutchik[["기대"]] %||% NA_real_)
    
    output_df$P <- as.numeric(pad[["P"]] %||% NA_real_)
    output_df$A <- as.numeric(pad[["A"]] %||% NA_real_)
    output_df$D <- as.numeric(pad[["D"]] %||% NA_real_)
    
    output_df$combinated_emotion <- as.character(parsed_data$combinated_emotion %||% "파싱 오류")
    output_df$complex_emotion <- as.character(parsed_data$complex_emotion %||% NA_character_)
    output_df$rationale <- as.character(parsed_data$rationale %||% NA_character_)
    
    return(output_df)
    
  }, error = function(e) {
    output_df$combinated_emotion <- "파싱 오류"
    output_df$error_message <- paste("JSON 파싱 실패:", e$message)
    # 원본 텍스트를 rationale에 저장하여 디버깅 지원
    output_df$rationale <- paste("Original non-JSON response:", json_text)
    return(output_df)
  })
}


# 3. 메인 감정분석 함수 (안정성 강화 버전)
analyze_emotion_robust <- function(
    prompt_text,
    model_to_use = "2.5-flash-lite-preview-06-17",
    temp_to_use = 0.3,
    top_p_to_use = 0.9,
    max_retries = 3) {
  
  # 항상 일관된 구조를 반환하기 위한 템플릿
  output_df <- data.frame(
    기쁨 = NA_real_, 신뢰 = NA_real_, 공포 = NA_real_, 놀람 = NA_real_,
    슬픔 = NA_real_, 혐오 = NA_real_, 분노 = NA_real_, 기대 = NA_real_,
    P = NA_real_, A = NA_real_, D = NA_real_,
    combinated_emotion = NA_character_,
    complex_emotion = NA_character_,
    rationale = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  emotion_schema <- list(
    type = "OBJECT",
    properties = list(
      plutchik_emotions = list(type = "OBJECT", properties = list(
        "기쁨" = list(type = "NUMBER", minimum = 0, maximum = 1), "신뢰" = list(type = "NUMBER", minimum = 0, maximum = 1),
        "공포" = list(type = "NUMBER", minimum = 0, maximum = 1), "놀람" = list(type = "NUMBER", minimum = 0, maximum = 1),
        "슬픔" = list(type = "NUMBER", minimum = 0, maximum = 1), "혐오" = list(type = "NUMBER", minimum = 0, maximum = 1),
        "분노" = list(type = "NUMBER", minimum = 0, maximum = 1), "기대" = list(type = "NUMBER", minimum = 0, maximum = 1)
      ), required = c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대")),
      PAD = list(type = "OBJECT", properties = list(
        P = list(type = "NUMBER", minimum = -1, maximum = 1), A = list(type = "NUMBER", minimum = -1, maximum = 1), D = list(type = "NUMBER", minimum = -1, maximum = 1)
      ), required = c("P", "A", "D")),
      combinated_emotion = list(type = "STRING"),
      complex_emotion = list(type = "STRING"),
      rationale = list(type = "STRING")
    ),
    required = c("plutchik_emotions", "PAD", "combinated_emotion", "complex_emotion", "rationale")
  )
  
  response_text <- NULL
  
  for (attempt in 1:max_retries) {
    response_text <- NULL # 각 시도마다 초기화
    tryCatch({
      response <- gemini_structured(
        prompt = prompt_text, schema = emotion_schema, model = model_to_use,
        temperature = temp_to_use, topP = top_p_to_use
      )
      response_text <- response # 성공 시 텍스트 저장
      
      # 성공적으로 API 호출 및 응답 받으면 루프 종료
      if (!is.null(response_text)) break
      
    }, error = function(e) {
      cat(sprintf("시도 %d/%d API 호출 실패: %s\n", attempt, max_retries, e$message))
      if (attempt == max_retries) {
        # 최종 실패 시 에러 메시지 저장
        response_text <<- paste("API Error after retries:", e$message)
      } else {
        Sys.sleep(2^attempt) # Exponential backoff
      }
    })
  }
  
  # API 호출이 최종 실패했거나 응답이 없는 경우
  if (is.null(response_text) || grepl("^API Error", response_text)) {
    output_df$combinated_emotion <- "API 오류"
    output_df$error_message <- response_text %||% "최대 재시도 후에도 API 응답 없음"
    return(output_df)
  }
  
  # 응답 파싱
  parsed_result_df <- parse_emotion_response(response_text)
  return(parsed_result_df)
}


cat("✅ 통합 함수 파일 로드 완료 (안정성 강화 버전)\n")
cat("📝 사용 가능한 함수:\n")
cat("  - create_analysis_prompt(): 프롬프트 생성\n")
cat("  - analyze_emotion_robust(): 감정분석 실행\n")
cat("  - parse_emotion_response(): API 응답 파싱\n")
