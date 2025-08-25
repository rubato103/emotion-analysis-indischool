# 배치 결과 파싱 수정 테스트 스크립트
setwd("C:/Users/rubat/SynologyDrive/R_project/emotion-analysis-indischool")

# 라이브러리 로드
library(jsonlite)

# JSONL 파일 경로
jsonl_file <- "results/batch_raw_batch-ds9rstbb50j0zvdt46rk8dxa5a7cmesrlawb_20250826_001343.jsonl"

cat("=== 배치 결과 파싱 테스트 ===\n")

if (file.exists(jsonl_file)) {
  cat("✅ JSONL 파일 발견:", basename(jsonl_file), "\n")
  
  # 첫 번째 라인 읽기
  lines <- readLines(jsonl_file, n = 2)
  cat("✅ 총", length(lines), "라인 읽음\n")
  
  # 첫 번째 결과 파싱 테스트
  cat("\n=== 첫 번째 결과 구조 분석 ===\n")
  result_item <- fromJSON(lines[1])
  
  cat("Key:", result_item$key, "\n")
  cat("Response 존재:", !is.null(result_item$response), "\n")
  
  if (!is.null(result_item$response$candidates)) {
    cat("Candidates 수:", length(result_item$response$candidates), "\n")
    
    if (length(result_item$response$candidates) > 0) {
      candidate <- result_item$response$candidates[[1]]
      cat("Content parts 존재:", !is.null(candidate$content$parts), "\n")
      
      if (!is.null(candidate$content$parts) && length(candidate$content$parts) > 0) {
        text <- candidate$content$parts[[1]]$text
        cat("Text 길이:", nchar(text), "\n")
        cat("Text 미리보기 (첫 200자):\n")
        cat(substr(text, 1, 200), "\n\n")
        
        # JSON 블록 추출 테스트
        if (grepl("```json", text)) {
          cat("✅ JSON 코드 블록 감지됨\n")
          
          # JSON 블록 추출
          json_match <- regmatches(text, regexpr("```json\\s*\\n(.+?)\\n```", text, perl = TRUE))
          if (length(json_match) > 0) {
            # ```json과 ``` 제거
            clean_json <- gsub("^```json\\s*\\n|\\n```$", "", json_match)
            cat("추출된 JSON:\n")
            cat(clean_json, "\n\n")
            
            # JSON 파싱 테스트
            tryCatch({
              emotion_data <- fromJSON(clean_json)
              cat("✅ JSON 파싱 성공!\n")
              
              if (!is.null(emotion_data$dominant_emotion)) {
                cat("지배감정:", emotion_data$dominant_emotion, "\n")
              }
              if (!is.null(emotion_data$plutchik_emotions)) {
                cat("기쁨 점수:", emotion_data$plutchik_emotions$기쁨, "\n")
              }
            }, error = function(e) {
              cat("❌ JSON 파싱 실패:", e$message, "\n")
            })
          }
        }
      }
    }
  }
} else {
  cat("❌ JSONL 파일을 찾을 수 없습니다:", jsonl_file, "\n")
}