# 통합 함수 정의 파일 (2025-08-27 최종 수정)

# 필수 패키지 로드
suppressMessages({
  library(jsonlite, quietly = TRUE)
  library(dplyr, quietly = TRUE)
  library(gemini.R, quietly = TRUE)
})

# Null-coalescing operator
`%||%` <- function(lhs, rhs) {
  if (!is.null(lhs) && length(lhs) > 0 && !is.na(lhs) && lhs != "") lhs else rhs
}

# 1. 프롬프트 생성 함수 (depth 및 parent_comment 지원)
create_analysis_prompt <- function(text, 구분, title = NULL, context = NULL, context_title = NULL, parent_comment = NULL, batch_mode = FALSE) {
  if (!exists("EMOTION_SCHEMA")) stop("❌ EMOTION_SCHEMA가 로드되지 않았습니다.")

  # 기본 지시사항과 JSON 구조를 프롬프트에 항상 포함
  base_instructions <- paste(PROMPT_CONFIG$base_instructions, PROMPT_CONFIG$json_structure, sep = "\n\n")
  
  # 배치 모드일 경우, 추가 지시사항만 덧붙임
  if (batch_mode) {
    base_instructions <- paste0(base_instructions, PROMPT_CONFIG$batch_json_instruction)
  }
  
  # 헤더 정의
  post_context_header <- PROMPT_CONFIG$context_header
  parent_comment_header <- "# 상위 댓글 (직접적인 맥락)"
  target_comment_header <- PROMPT_CONFIG$comment_header
  target_post_header <- PROMPT_CONFIG$post_header

  final_prompt_parts <- c(base_instructions)

  if (구분 == "댓글") {
    final_prompt_parts <- c(final_prompt_parts, PROMPT_CONFIG$comment_task)
    if (!is.null(context) && !is.na(context)) {
      full_post_context <- if (!is.null(context_title) && !is.na(context_title)) paste(context_title, context, sep = "\n\n") else context
      final_prompt_parts <- c(final_prompt_parts, post_context_header, full_post_context)
    }
    if (!is.null(parent_comment) && !is.na(parent_comment)) {
      final_prompt_parts <- c(final_prompt_parts, parent_comment_header, parent_comment)
    }
    final_prompt_parts <- c(final_prompt_parts, target_comment_header, text)
  } else {
    final_prompt_parts <- c(final_prompt_parts, PROMPT_CONFIG$post_task)
    full_text_post <- if (!is.null(title) && !is.na(title)) paste(title, text, sep = "\n\n") else text
    final_prompt_parts <- c(final_prompt_parts, target_post_header, full_text_post)
  }
  
  return(paste(final_prompt_parts, collapse = "\n\n"))
}

# 2. 통합 JSON 파싱 함수 (확장된 스키마 전용)
parse_emotion_response <- function(json_text) {
  # 항상 일관된 구조를 반환하기 위한 템플릿
  output_df <- data.frame(
    기쁨 = NA_real_, 신뢰 = NA_real_, 공포 = NA_real_, 놀람 = NA_real_,
    슬픔 = NA_real_, 혐오 = NA_real_, 분노 = NA_real_, 기대 = NA_real_,
    P = NA_real_, A = NA_real_, D = NA_real_,
    emotion_source = NA_character_,
    emotion_direction = NA_character_,
    combinated_emotion = NA_character_,
    complex_emotion = NA_character_,
    rationale = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE, check.names = FALSE
  )
  
  tryCatch({
    if (is.null(json_text) || json_text == "") stop("API 응답이 비어있습니다.")
    
    response_clean <- gsub("```json[[:space:]]*|[[:space:]]*```", "", json_text, perl = TRUE) %>% trimws()
    if (nchar(response_clean) == 0) stop("정리 후 내용이 비어있습니다.")
    
    parsed_data <- jsonlite::fromJSON(response_clean, flatten = TRUE)
    
    required_fields <- c("plutchik_emotions", "PAD", "emotion_target", "combinated_emotion", "complex_emotion", "rationale")
    if (!all(required_fields %in% names(parsed_data))) stop("응답에 필수 필드가 누락되었습니다.")
    
    plutchik <- parsed_data$plutchik_emotions
    pad <- parsed_data$PAD
    
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
    
    emotion_target <- parsed_data$emotion_target
    output_df$emotion_source <- as.character(emotion_target[["source"]] %||% "파싱 오류")
    output_df$emotion_direction <- as.character(emotion_target[["direction"]] %||% "파싱 오류")
    output_df$combinated_emotion <- as.character(parsed_data$combinated_emotion %||% NA_character_)
    output_df$complex_emotion <- as.character(parsed_data$complex_emotion %||% NA_character_)
    output_df$rationale <- as.character(parsed_data$rationale %||% NA_character_)
    
    return(output_df)
    
  }, error = function(e) {
    output_df$emotion_source <- "파싱 오류"
    output_df$emotion_direction <- "파싱 오류"
    output_df$error_message <- paste("JSON 파싱 실패:", e$message)
    output_df$rationale <- paste("Original non-JSON response:", substr(json_text, 1, 500))
    return(output_df)
  })
}

# 3. 메인 감정분석 함수 (중앙 스키마, 확장된 구조 사용)
analyze_emotion_robust <- function(
    prompt_text,
    model_to_use = API_CONFIG$model_name,
    temp_to_use = API_CONFIG$temperature,
    top_p_to_use = API_CONFIG$top_p,
    max_retries = API_CONFIG$max_retries) {

  # 항상 일관된 구조를 반환하기 위한 템플릿
  output_df <- data.frame(
    기쁨 = NA_real_, 신뢰 = NA_real_, 공포 = NA_real_, 놀람 = NA_real_,
    슬픔 = NA_real_, 혐오 = NA_real_, 분노 = NA_real_, 기대 = NA_real_,
    P = NA_real_, A = NA_real_, D = NA_real_,
    emotion_source = NA_character_,
    emotion_direction = NA_character_,
    combinated_emotion = NA_character_,
    complex_emotion = NA_character_,
    rationale = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE, check.names = FALSE
  )

  if (!exists("EMOTION_SCHEMA")) stop("❌ EMOTION_SCHEMA가 로드되지 않았습니다. config.R을 확인하세요.")

  response_text <- NULL
  
  for (attempt in 1:max_retries) {
    response_text <- NULL
    tryCatch({
      response <- gemini_structured(
        prompt = prompt_text, 
        schema = EMOTION_SCHEMA, 
        model = model_to_use,
        temperature = temp_to_use, 
        topP = top_p_to_use
      )
      response_text <- response
      if (!is.null(response_text)) break
      
    }, error = function(e) {
      cat(sprintf("시도 %d/%d API 호출 실패: %s\n", attempt, max_retries, e$message))
      if (attempt == max_retries) {
        response_text <<- paste("API Error after retries:", e$message)
      } else {
        Sys.sleep(2^attempt)
      }
    })
  }
  
  # API 호출이 최종 실패한 경우, 여기서 직접 에러 DF를 반환
  if (is.null(response_text) || grepl("^API Error", response_text)) {
    output_df$emotion_source <- "API 오류"
    output_df$emotion_direction <- "API 오류"
    output_df$error_message <- response_text %||% "최대 재시도 후에도 API 응답 없음"
    return(output_df)
  }

  # 성공 시, 파싱 함수 호출
  return(parse_emotion_response(response_text))
}

cat("✅ 통합 함수 파일 로드 완료 (2025-08-27 최종 수정)\n")