# 배치 결과 파싱 및 Parquet 저장 최종 스크립트
# 목적: 배치 결과를 올바르게 파싱하고 Parquet 형식으로 저장

library(arrow)
library(dplyr)
library(jsonlite)

# JSONL 파일에서 결과 로드
jsonl_file <- "results/batch_raw_batch-v54vae0nhoe5tmep1fqiiq1zoi7f62mxl8b0_20250828_204639.jsonl"
cat("JSONL 파일 로드:", jsonl_file, "\n")

# JSONL 파일의 내용을 라인별로 읽기
result_lines <- readLines(jsonl_file)
cat("총", length(result_lines), "개의 결과 라인 발견\n")

# 각 라인을 JSON으로 파싱
results <- vector("list", length(result_lines))
for (i in seq_along(result_lines)) {
  if (result_lines[i] != "") {
    results[[i]] <- jsonlite::fromJSON(result_lines[i])
  }
}

# 결과가 비어있지 않은 항목만 필터링
results <- results[!sapply(results, is.null)]
cat("유효한 결과:", length(results), "개\n")

# 배치 결과를 데이터프레임으로 변환
convert_batch_results_to_df <- function(results) {
  # 결과를 데이터프레임으로 변환
  parsed_data <- vector("list", length(results))
  
  for (i in seq_along(results)) {
    result_item <- results[[i]]
    
    # 기본 정보
    key <- if (!is.null(result_item$key)) result_item$key else paste0("item_", i)
    
    # 응답 텍스트 추출
    response_text <- NULL
    tryCatch({
      # candidates가 data.frame인지 확인
      if (!is.null(result_item$response) && 
          !is.null(result_item$response$candidates)) {
        
        # candidates가 data.frame인 경우
        if (is.data.frame(result_item$response$candidates)) {
          if (nrow(result_item$response$candidates) > 0) {
            # 첫 번째 행에서 content 추출
            first_candidate <- result_item$response$candidates[1, ]
            
            # content가 data.frame인지 확인
            if (!is.null(first_candidate$content) && is.data.frame(first_candidate$content)) {
              if (nrow(first_candidate$content) > 0) {
                # parts가 list인지 확인
                if (!is.null(first_candidate$content$parts) && is.list(first_candidate$content$parts)) {
                  # 첫 번째 parts 요소가 data.frame인지 확인
                  if (length(first_candidate$content$parts) > 0 && is.data.frame(first_candidate$content$parts[[1]])) {
                    first_part <- first_candidate$content$parts[[1]]
                    if (nrow(first_part) > 0 && !is.null(first_part$text)) {
                      response_text <- first_part$text[1]
                    }
                  }
                }
              }
            }
          }
        }
      }
    }, error = function(e) {
      cat("응답 텍스트 추출 중 오류 (항목", i, "):", e$message, "\n")
    })
    
    if (!is.null(response_text) && response_text != "") {
      # JSON 파싱
      # 코드 블록 마커 제거
      json_text <- gsub("^```json\\n?", "", response_text)
      json_text <- gsub("\\n?```$", "", json_text)
      
      tryCatch({
        emotion_data <- jsonlite::fromJSON(json_text)
        
        # 기본 정보 추출
        row_data <- list(
          key = key,
          기쁨 = if (!is.null(emotion_data$plutchik_emotions$기쁨)) emotion_data$plutchik_emotions$기쁨 else NA,
          신뢰 = if (!is.null(emotion_data$plutchik_emotions$신뢰)) emotion_data$plutchik_emotions$신뢰 else NA,
          공포 = if (!is.null(emotion_data$plutchik_emotions$공포)) emotion_data$plutchik_emotions$공포 else NA,
          놀람 = if (!is.null(emotion_data$plutchik_emotions$놀람)) emotion_data$plutchik_emotions$놀람 else NA,
          슬픔 = if (!is.null(emotion_data$plutchik_emotions$슬픔)) emotion_data$plutchik_emotions$슬픔 else NA,
          혐오 = if (!is.null(emotion_data$plutchik_emotions$혐오)) emotion_data$plutchik_emotions$혐오 else NA,
          분노 = if (!is.null(emotion_data$plutchik_emotions$분노)) emotion_data$plutchik_emotions$분노 else NA,
          기대 = if (!is.null(emotion_data$plutchik_emotions$기대)) emotion_data$plutchik_emotions$기대 else NA,
          P = if (!is.null(emotion_data$PAD$P)) emotion_data$PAD$P else NA,
          A = if (!is.null(emotion_data$PAD$A)) emotion_data$PAD$A else NA,
          D = if (!is.null(emotion_data$PAD$D)) emotion_data$PAD$D else NA,
          emotion_source = if (!is.null(emotion_data$emotion_target$source)) emotion_data$emotion_target$source else NA,
          emotion_direction = if (!is.null(emotion_data$emotion_target$direction)) emotion_data$emotion_target$direction else NA,
          combinated_emotion = if (!is.null(emotion_data$combinated_emotion)) emotion_data$combinated_emotion else NA,
          complex_emotion = if (!is.null(emotion_data$complex_emotion)) emotion_data$complex_emotion else NA,
          rationale = if (!is.null(emotion_data$rationale)) emotion_data$rationale else NA,
          error_message = NA
        )
        
        parsed_data[[i]] <- row_data
      }, error = function(e) {
        # 파싱 오류 처리
        row_data <- list(
          key = key,
          기쁨 = NA,
          신뢰 = NA,
          공포 = NA,
          놀람 = NA,
          슬픔 = NA,
          혐오 = NA,
          분노 = NA,
          기대 = NA,
          P = NA,
          A = NA,
          D = NA,
          emotion_source = NA,
          emotion_direction = NA,
          combinated_emotion = "파싱 오류",
          complex_emotion = NA,
          rationale = paste("JSON 파싱 실패:", e$message),
          error_message = e$message
        )
        parsed_data[[i]] <- row_data
      })
    } else {
      # 응답이 없는 경우
      row_data <- list(
        key = key,
        기쁨 = NA,
        신뢰 = NA,
        공포 = NA,
        놀람 = NA,
        슬픔 = NA,
        혐오 = NA,
        분노 = NA,
        기대 = NA,
        P = NA,
        A = NA,
        D = NA,
        emotion_source = NA,
        emotion_direction = NA,
        combinated_emotion = "응답 없음",
        complex_emotion = NA,
        rationale = "API 응답이 없습니다",
        error_message = "API 응답이 없습니다"
      )
      parsed_data[[i]] <- row_data
    }
  }
  
  # 데이터프레임으로 변환
  if (length(parsed_data) > 0) {
    df <- do.call(rbind.data.frame, parsed_data)
    # 열 타입 정리
    numeric_cols <- c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대", "P", "A", "D")
    for (col in numeric_cols) {
      if (col %in% names(df)) {
        df[[col]] <- as.numeric(df[[col]])
      }
    }
    return(df)
  } else {
    return(data.frame())
  }
}

# 결과를 데이터프레임으로 변환
cat("\n결과를 데이터프레임으로 변환 중...\n")
result_df <- convert_batch_results_to_df(results)

cat("변환된 데이터프레임 구조:\n")
print(str(result_df))

# 결과 확인
if (nrow(result_df) > 0) {
  cat("\n변환된 데이터의 처음 몇 행:\n")
  print(head(result_df))
  
  # Parquet 파일로 저장
  parquet_file <- "results/batch_parsed_test.parquet"
  cat("\nParquet 파일로 저장 중:", parquet_file, "\n")
  
  tryCatch({
    arrow::write_parquet(result_df, parquet_file, compression = "snappy")
    cat("✅ Parquet 파일 저장 성공!\n")
    
    # 저장된 파일 확인
    saved_df <- arrow::read_parquet(parquet_file)
    cat("저장된 파일의 행 수:", nrow(saved_df), "\n")
    cat("저장된 파일의 열 수:", ncol(saved_df), "\n")
    cat("열 이름:", names(saved_df), "\n")
    
    # 첫 몇 행 표시
    cat("\n저장된 데이터의 처음 몇 행:\n")
    print(head(saved_df))
  }, error = function(e) {
    cat("❌ Parquet 파일 저장 실패:", e$message, "\n")
  })
} else {
  cat("변환된 데이터가 없습니다.\n")
}

cat("\n테스트 완료!\n")