# 통합 함수 정의 파일
# 모든 필요한 함수들을 하나의 파일로 통합

# 필수 패키지 로드 확인 - 단순화된 버전
suppressMessages({
  if (!("jsonlite" %in% rownames(installed.packages()))) {
    install.packages("jsonlite", repos = "https://cran.rstudio.com/", type = "binary")
  }
  library(jsonlite, quietly = TRUE)
  
  if (!("dplyr" %in% rownames(installed.packages()))) {
    install.packages("dplyr", repos = "https://cran.rstudio.com/", type = "binary")
  }
  library(dplyr, quietly = TRUE)
})

# httr2 will be loaded separately when needed for API calls

# Null-coalescing operator 정의
`%||%` <- function(lhs, rhs) {
  if (!is.null(lhs) && length(lhs) > 0 && !is.na(lhs)) lhs else rhs
}

# 1. 프롬프트 생성 함수 (config.R의 PROMPT_CONFIG 사용)
create_analysis_prompt <- function(text, 구분, title = NULL, context = NULL, context_title = NULL) {
  
  # config.R에서 프롬프트 설정 로드 (필수)
  if (!exists("PROMPT_CONFIG")) {
    stop("❌ PROMPT_CONFIG가 로드되지 않았습니다. config.R을 먼저 로드해주세요: source('config.R')")
  }
  
  base_instructions <- PROMPT_CONFIG$base_instructions
  comment_task <- PROMPT_CONFIG$comment_task
  post_task <- PROMPT_CONFIG$post_task
  context_header <- PROMPT_CONFIG$context_header
  comment_header <- PROMPT_CONFIG$comment_header
  post_header <- PROMPT_CONFIG$post_header
  
  # 프롬프트 조합
  if (구분 == "댓글") {
    # 댓글 분석
    full_context <- if (!is.null(context_title) && !is.na(context_title)) paste(context_title, context, sep = "\n\n") else context
    
    final_prompt <- paste0(
      base_instructions, "\n\n",
      comment_task, "\n\n",
      context_header, "\n", full_context, "\n\n",
      comment_header, "\n", text
    )
  } else {
    # 게시글 분석
    full_text_post <- if (!is.null(title) && !is.na(title)) paste(title, text, sep = "\n\n") else text
    
    final_prompt <- paste0(
      base_instructions, "\n\n",
      post_task, "\n\n",
      post_header, "\n", full_text_post
    )
  }
  
  return(final_prompt)
}

# 2. gemini.R 패키지 확인 및 로드 (단순화)
ensure_gemini_package <- function() {
  if (!require("gemini.R", quietly = TRUE)) {
    cat("📦 gemini.R 패키지를 설치합니다...\n")
    install.packages("gemini.R")
    library(gemini.R)
  }
  return(TRUE)
}

# 3. JSON 응답 파싱 함수
parse_emotion_json_internal <- function(json_text) {
  # JSON 정리
  response_clean <- gsub("```json\\s*|\\s*```", "", json_text, perl = TRUE)
  response_clean <- gsub("^\\s+|\\s+$", "", response_clean)
  response_clean <- gsub("[\\x00-\\x1F\\x7F-\\x9F]", "", response_clean)
  response_clean <- gsub("\\ufffd", "", response_clean)
  response_clean <- iconv(response_clean, to = "UTF-8", sub = "")
  
  # JSON 파싱
  parsed_data <- jsonlite::fromJSON(response_clean, flatten = TRUE)
  
  # 필수 필드 확인
  if (!all(c("emotion_scores", "PAD", "dominant_emotion", "rationale") %in% names(parsed_data))) {
    stop("응답에 필수 필드가 없습니다")
  }
  
  emotion_scores <- parsed_data$emotion_scores
  pad_scores <- parsed_data$PAD
  
  # 결과 구조 생성
  result <- list(
    기쁨 = as.numeric(emotion_scores[["기쁨"]] %||% NA_real_),
    슬픔 = as.numeric(emotion_scores[["슬픔"]] %||% NA_real_),
    분노 = as.numeric(emotion_scores[["분노"]] %||% NA_real_),
    혐오 = as.numeric(emotion_scores[["혐오"]] %||% NA_real_),
    공포 = as.numeric(emotion_scores[["공포"]] %||% NA_real_),
    놀람 = as.numeric(emotion_scores[["놀람"]] %||% NA_real_),
    `애정/사랑` = as.numeric(emotion_scores[["애정/사랑"]] %||% NA_real_),
    중립 = as.numeric(emotion_scores[["중립"]] %||% NA_real_),
    P = as.numeric(pad_scores[["P"]] %||% NA_real_),
    A = as.numeric(pad_scores[["A"]] %||% NA_real_),
    D = as.numeric(pad_scores[["D"]] %||% NA_real_),
    PAD_complex_emotion = as.character(parsed_data$PAD_complex_emotion %||% NA_character_),
    dominant_emotion = as.character(parsed_data$dominant_emotion %||% NA_character_),
    rationale = as.character(parsed_data$rationale %||% NA_character_),
    unexpected_emotions = as.character(parsed_data$unexpected_emotions %||% NA_character_),
    error_message = NA_character_
  )
  
  return(result)
}

# 4. 메인 감정분석 함수 (작동 확인된 버전)
analyze_emotion_robust <- function(prompt_text,
                                   model_to_use = "2.5-flash-lite-preview-06-17",
                                   temp_to_use = 0.3,
                                   top_p_to_use = 0.9,
                                   max_retries = 5) {
  
  # gemini.R 패키지 확인
  if (!require("gemini.R", quietly = TRUE)) {
    stop("gemini.R 패키지가 설치되지 않았습니다.")
  }
  
  # 감정분석용 JSON 스키마 정의 (플루치크 8대 기본감정)
  emotion_schema <- list(
    type = "OBJECT",
    properties = list(
      plutchik_emotions = list(
        type = "OBJECT",
        properties = list(
          "기쁨" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "신뢰" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "공포" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "놀람" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "슬픔" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "혐오" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "분노" = list(type = "NUMBER", minimum = 0, maximum = 1),
          "기대" = list(type = "NUMBER", minimum = 0, maximum = 1)
        ),
        required = c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대")
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
      dominant_emotion = list(type = "STRING"),
      complex_emotion = list(type = "STRING"),
      rationale = list(
        type = "OBJECT",
        properties = list(
          emotion_scores = list(type = "STRING"),
          PAD_analysis = list(type = "STRING"),
          complex_emotion_reasoning = list(type = "STRING")
        ),
        required = c("emotion_scores", "PAD_analysis", "complex_emotion_reasoning")
      )
    ),
    required = c("plutchik_emotions", "PAD", "dominant_emotion", "complex_emotion", "rationale")
  )
  
  # 출력 구조 정의 (플루치크 8대 기본감정)
  output_df <- data.frame(
    기쁨 = NA_real_, 신뢰 = NA_real_, 공포 = NA_real_, 놀람 = NA_real_,
    슬픔 = NA_real_, 혐오 = NA_real_, 분노 = NA_real_, 기대 = NA_real_,
    P = NA_real_, A = NA_real_, D = NA_real_,
    dominant_emotion = NA_character_,
    complex_emotion = NA_character_,
    emotion_scores_rationale = NA_character_,
    PAD_analysis = NA_character_,
    complex_emotion_reasoning = NA_character_,
    error_message = NA_character_,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  
  # 재시도 로직
  for (attempt in 1:max_retries) {
    tryCatch({
      # gemini_structured 호출 (원본 작동 방식)
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
      
      # 데이터 추출 및 검증 (새로운 구조)
      if (all(c("plutchik_emotions", "PAD", "dominant_emotion", "complex_emotion", "rationale") %in% names(parsed_data))) {
        
        plutchik_emotions <- parsed_data$plutchik_emotions
        pad_scores <- parsed_data$PAD
        rationale <- parsed_data$rationale
        
        # 플루치크 8대 기본감정 추출
        output_df$기쁨 <- as.numeric(plutchik_emotions[["기쁨"]] %||% NA_real_)
        output_df$신뢰 <- as.numeric(plutchik_emotions[["신뢰"]] %||% NA_real_)
        output_df$공포 <- as.numeric(plutchik_emotions[["공포"]] %||% NA_real_)
        output_df$놀람 <- as.numeric(plutchik_emotions[["놀람"]] %||% NA_real_)
        output_df$슬픔 <- as.numeric(plutchik_emotions[["슬픔"]] %||% NA_real_)
        output_df$혐오 <- as.numeric(plutchik_emotions[["혐오"]] %||% NA_real_)
        output_df$분노 <- as.numeric(plutchik_emotions[["분노"]] %||% NA_real_)
        output_df$기대 <- as.numeric(plutchik_emotions[["기대"]] %||% NA_real_)
        
        # PAD 점수 추출
        output_df$P <- as.numeric(pad_scores[["P"]] %||% NA_real_)
        output_df$A <- as.numeric(pad_scores[["A"]] %||% NA_real_)
        output_df$D <- as.numeric(pad_scores[["D"]] %||% NA_real_)
        
        # 결과 및 근거 추출
        output_df$dominant_emotion <- as.character(parsed_data$dominant_emotion %||% NA_character_)
        output_df$complex_emotion <- as.character(parsed_data$complex_emotion %||% NA_character_)
        output_df$emotion_scores_rationale <- as.character(rationale[["emotion_scores"]] %||% NA_character_)
        output_df$PAD_analysis <- as.character(rationale[["PAD_analysis"]] %||% NA_character_)
        output_df$complex_emotion_reasoning <- as.character(rationale[["complex_emotion_reasoning"]] %||% NA_character_)
        
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

# 5. 배치 처리용 JSON 파싱 함수
parse_emotion_json <- function(json_text) {
  return(parse_emotion_json_internal(json_text))
}

# 6. 마크다운 형태 응답 파싱 함수 (배치 처리용)
parse_markdown_emotion_response <- function(markdown_text) {
  # 마크다운 응답에서 감정 점수와 PAD 점수 추출
  
  # 기본 결과 구조
  result <- list(
    기쁨 = NA_real_, 슬픔 = NA_real_, 분노 = NA_real_, 혐오 = NA_real_,
    공포 = NA_real_, 놀람 = NA_real_, `애정/사랑` = NA_real_, 중립 = NA_real_,
    P = NA_real_, A = NA_real_, D = NA_real_,
    PAD_complex_emotion = NA_character_,
    dominant_emotion = NA_character_,
    rationale = NA_character_,
    unexpected_emotions = NA_character_,
    error_message = NA_character_
  )
  
  tryCatch({
    cat("📝 마크다운 파싱 시작\n")
    cat("응답 텍스트 샘플 (첫 200자):\n")
    cat(substr(markdown_text, 1, 200), "\n")
    
    # 감정 점수 추출
    result$기쁨 <- extract_emotion_score(markdown_text, "기쁨")
    result$슬픔 <- extract_emotion_score(markdown_text, "슬픔")
    result$분노 <- extract_emotion_score(markdown_text, "분노")
    result$혐오 <- extract_emotion_score(markdown_text, "혐오")
    result$공포 <- extract_emotion_score(markdown_text, "공포")
    result$놀람 <- extract_emotion_score(markdown_text, "놀람")
    result$`애정/사랑` <- extract_emotion_score(markdown_text, "애정/사랑")
    result$중립 <- extract_emotion_score(markdown_text, "중립")
    
    # PAD 점수 추출
    result$P <- extract_pad_score(markdown_text, "P|쾌락|긍정성")
    result$A <- extract_pad_score(markdown_text, "A|각성|활성도")
    result$D <- extract_pad_score(markdown_text, "D|지배|통제감")
    
    # 복합 감정 추출
    result$PAD_complex_emotion <- extract_complex_emotion(markdown_text)
    cat(sprintf("DEBUG: 추출된 복합 감정: '%s'\n", result$PAD_complex_emotion))
    
    # 지배 감정 추출
    result$dominant_emotion <- extract_dominant_emotion(markdown_text)
    cat(sprintf("DEBUG: 추출된 지배 감정: '%s'\n", result$dominant_emotion))
    
    # 추출 실패한 경우 기본값 설정
    if (is.na(result$dominant_emotion) || result$dominant_emotion == "") {
      cat("⚠️ 지배 감정 추출 실패, 기본값 설정\n")
      result$dominant_emotion <- "파싱 불완전"
    }
    
    # 분석 근거 추출
    result$rationale <- extract_rationale(markdown_text)
    
    cat("✅ 마크다운 파싱 완료\n")
    return(result)
  }, error = function(e) {
    cat(sprintf("❌ 마크다운 파싱 오류: %s\n", e$message))
    result$dominant_emotion <- "마크다운 파싱 오류"
    result$error_message <- paste("마크다운 파싱 실패:", e$message)
    return(result)
  })
}

# 마크다운에서 감정 점수 추출 헬퍼 함수
extract_emotion_score <- function(text, emotion_name) {
  pattern <- paste0("\\*\\*", emotion_name, "\\*\\*:?\\s*([0-9.]+)")
  matches <- regmatches(text, regexpr(pattern, text, perl = TRUE))
  if (length(matches) > 0) {
    score_text <- gsub(pattern, "\\1", matches, perl = TRUE)
    return(as.numeric(score_text))
  }
  return(NA_real_)
}

# 마크다운에서 PAD 점수 추출 헬퍼 함수  
extract_pad_score <- function(text, pad_pattern) {
  pattern <- paste0("\\*\\*(", pad_pattern, ").*?\\*\\*:?\\s*([-0-9.]+)")
  matches <- regmatches(text, regexpr(pattern, text, perl = TRUE))
  if (length(matches) > 0) {
    score_text <- gsub(pattern, "\\2", matches, perl = TRUE)
    return(as.numeric(score_text))
  }
  return(NA_real_)
}

# 복합 감정 추출
extract_complex_emotion <- function(text) {
  # 여러 패턴 시도
  patterns <- c(
    "\\*\\*복합\\s*감정\\*\\*:?\\s*\\*\\*([^*]+)\\*\\*",  # **복합 감정**: **감정명**
    "\\*\\s*\\*\\*복합\\s*감정\\*\\*:?\\s*\\*\\*([^*]+)\\*\\*",  # * **복합 감정**: **감정명**
    "복합\\s*감정:?\\s*\\*\\*([^*]+)\\*\\*",  # 복합 감정: **감정명**
    "복합\\s*감정:?\\s*([^\\n]+)",  # 복합 감정: 감정명
    "\\*\\*복합\\s*감정\\*\\*:?\\s*([^\\n]+)"  # **복합 감정**: 감정명
  )
  
  for (pattern in patterns) {
    matches <- regmatches(text, regexpr(pattern, text, perl = TRUE))
    if (length(matches) > 0) {
      result <- gsub(pattern, "\\1", matches, perl = TRUE)
      result <- trimws(result)
      result <- gsub("\\*+", "", result)  # 남은 * 제거
      if (nchar(result) > 0) {
        return(result)
      }
    }
  }
  return(NA_character_)
}

# 지배 감정 추출
extract_dominant_emotion <- function(text) {
  # 여러 패턴 시도
  patterns <- c(
    "\\*\\*지배\\s*감정\\*\\*:?\\s*\\*\\*([^*]+)\\*\\*",  # **지배 감정**: **감정명**
    "\\*\\s*\\*\\*지배\\s*감정\\*\\*:?\\s*\\*\\*([^*]+)\\*\\*",  # * **지배 감정**: **감정명**
    "지배\\s*감정:?\\s*\\*\\*([^*]+)\\*\\*",  # 지배 감정: **감정명**
    "지배\\s*감정:?\\s*([가-힣]+)",  # 지배 감정: 감정명
    "\\*\\*지배\\s*감정\\*\\*:?\\s*([가-힣]+)"  # **지배 감정**: 감정명
  )
  
  for (pattern in patterns) {
    matches <- regmatches(text, regexpr(pattern, text, perl = TRUE))
    if (length(matches) > 0) {
      result <- gsub(pattern, "\\1", matches, perl = TRUE)
      result <- trimws(result)
      if (nchar(result) > 0) {
        return(result)
      }
    }
  }
  return(NA_character_)
}

# 분석 근거 추출
extract_rationale <- function(text) {
  # 분석 근거 제시 섹션 찾기
  pattern <- "\\*\\*분석\\s*근거\\s*제시\\*\\*:?([\\s\\S]*?)(?=\\n\\n|$)"
  matches <- regmatches(text, regexpr(pattern, text, perl = TRUE))
  if (length(matches) > 0) {
    rationale <- gsub(pattern, "\\1", matches, perl = TRUE)
    # 마크다운 정리
    rationale <- gsub("\\*\\*([^*]+)\\*\\*", "\\1", rationale)  # 볼드 제거
    rationale <- gsub("\\*\\s*", "- ", rationale)  # 리스트 정리
    return(trimws(rationale))
  }
  return(NA_character_)
}

cat("✅ 통합 함수 파일 로드 완료\n")
cat("📝 사용 가능한 함수:\n")
cat("  - create_analysis_prompt(): 프롬프트 생성\n")
cat("  - analyze_emotion_robust(): 감정분석 실행\n")
cat("  - gemini_api_call(): 직접 API 호출\n")
cat("  - parse_emotion_json(): JSON 파싱\n")