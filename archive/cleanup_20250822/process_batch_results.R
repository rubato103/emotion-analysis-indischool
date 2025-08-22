# 배치 결과 처리 스크립트
# 목적: 저장된 JSONL 배치 결과를 03 스크립트 형식의 데이터프레임으로 변환

source("config.R")
source("utils.R")
source("functions.R")
source("human_coding.R")

# 필요한 패키지
required_packages <- c("dplyr", "jsonlite", "stringr", "readr", "googlesheets4", "googledrive")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)

# 배치 결과 파싱 함수
process_batch_jsonl <- function(jsonl_file, original_data = NULL) {
  if (!file.exists(jsonl_file)) {
    stop("JSONL 파일을 찾을 수 없습니다: ", jsonl_file)
  }
  
  cat(sprintf("📄 배치 결과 파일 처리 중: %s\n", basename(jsonl_file)))
  
  # JSONL 파일 읽기
  jsonl_lines <- readLines(jsonl_file, warn = FALSE)
  jsonl_lines <- jsonl_lines[jsonl_lines != ""]
  
  cat(sprintf("📊 총 %d개 응답 발견\n", length(jsonl_lines)))
  
  # 각 라인 파싱
  results <- vector("list", length(jsonl_lines))
  
  for (i in seq_along(jsonl_lines)) {
    tryCatch({
      line_data <- jsonlite::fromJSON(jsonl_lines[i])
      
      # 요청 키 추출 (배치 모니터 구조에 맞게)
      request_key <- line_data$metadata$key %||% paste0("request-", i)
      row_index <- as.numeric(gsub("request-", "", request_key))
      
      # 응답 텍스트 추출 (중첩 구조 고려)
      response_text <- NULL
      
      # 다양한 응답 구조 시도
      if (!is.null(line_data$response) && !is.null(line_data$response$candidates)) {
        if (length(line_data$response$candidates) > 0 && 
            !is.null(line_data$response$candidates[[1]]$content$parts[[1]]$text)) {
          response_text <- line_data$response$candidates[[1]]$content$parts[[1]]$text
        }
      }
      
      if (!is.null(response_text)) {
        
        # JSON 파싱 시도 (JSON과 마크다운 모두 처리)
        emotion_result <- tryCatch({
          # 먼저 JSON으로 파싱 시도
          cat(sprintf("JSON 파싱 시도 (응답 길이: %d)\n", nchar(response_text)))
          parse_emotion_json_internal(response_text)
        }, error = function(e) {
          # JSON 파싱 실패시 마크다운 파싱 시도
          cat(sprintf("JSON 파싱 실패, 마크다운 파싱 시도: %s\n", e$message))
          tryCatch({
            result <- parse_markdown_emotion_response(response_text)
            cat(sprintf("마크다운 파싱 성공, dominant_emotion: %s\n", result$dominant_emotion))
            return(result)
          }, error = function(e2) {
            cat(sprintf("마크다운 파싱도 실패: %s\n", e2$message))
            # 모든 파싱 실패시 기본 오류 응답
            list(
              기쁨 = NA_real_, 슬픔 = NA_real_, 분노 = NA_real_, 혐오 = NA_real_,
              공포 = NA_real_, 놀람 = NA_real_, `애정/사랑` = NA_real_, 중립 = NA_real_,
              P = NA_real_, A = NA_real_, D = NA_real_,
              PAD_complex_emotion = NA_character_,
              dominant_emotion = "파싱 오류",
              rationale = paste("파싱 실패:", e$message, e2$message),
              unexpected_emotions = NA_character_,
              error_message = paste("파싱 실패:", e$message, e2$message)
            )
          })
        })
        
        emotion_result$row_index <- row_index
        emotion_result$request_key <- request_key
        if (is.na(emotion_result$error_message)) {
          emotion_result$error_message <- NA_character_
        }
        
        results[[i]] <- emotion_result
        
      } else {
        # 빈 응답 처리
        results[[i]] <- list(
          row_index = row_index,
          request_key = request_key,
          dominant_emotion = "API 오류",
          rationale = "빈 응답",
          기쁨 = NA, 슬픔 = NA, 분노 = NA, 혐오 = NA,
          공포 = NA, 놀람 = NA, `애정/사랑` = NA, 중립 = NA,
          P = NA, A = NA, D = NA,
          PAD_complex_emotion = NA,
          unexpected_emotions = NA,
          error_message = "빈 응답"
        )
      }
      
    }, error = function(e) {
      cat(sprintf("⚠️ 라인 %d 파싱 오류: %s\n", i, e$message))
      
      results[[i]] <- list(
        row_index = i,
        request_key = sprintf("request-%d", i),
        dominant_emotion = "파싱 오류",
        rationale = sprintf("JSON 파싱 실패: %s", e$message),
        기쁨 = NA, 슬픔 = NA, 분노 = NA, 혐오 = NA,
        공포 = NA, 놀람 = NA, `애정/사랑` = NA, 중립 = NA,
        P = NA, A = NA, D = NA,
        PAD_complex_emotion = NA,
        unexpected_emotions = NA,
        error_message = sprintf("파싱 오류: %s", e$message)
      )
    })
  }
  
  # 데이터프레임으로 변환 (안전한 방법)
  cat("📊 결과를 데이터프레임으로 변환 중...\n")
  
  # 각 결과가 올바른 컬럼을 가지고 있는지 확인
  for (i in seq_along(results)) {
    if (!"dominant_emotion" %in% names(results[[i]])) {
      cat(sprintf("⚠️ 결과 %d에 dominant_emotion 컬럼 없음\n", i))
      results[[i]]$dominant_emotion <- "파싱 오류"
    }
    cat(sprintf("결과 %d: dominant_emotion = '%s'\n", i, results[[i]]$dominant_emotion))
  }
  
  # dplyr를 사용한 안전한 데이터프레임 변환
  results_df <- dplyr::bind_rows(results)
  
  cat(sprintf("✅ 파싱 완료: %d행\n", nrow(results_df)))
  cat("최종 데이터프레임 컬럼:\n")
  print(names(results_df))
  cat("dominant_emotion 컬럼 존재 여부:", "dominant_emotion" %in% names(results_df), "\n")
  
  # 원본 데이터와 병합 (만약 제공된다면)
  if (!is.null(original_data)) {
    final_df <- original_data %>%
      mutate(row_index = row_number()) %>%
      left_join(results_df, by = "row_index") %>%
      select(-row_index, -request_key)
    
    cat(sprintf("🔗 원본 데이터와 병합 완료: %d행\n", nrow(final_df)))
    return(final_df)
  }
  
  return(results_df)
}

# 메인 처리 함수
process_completed_batch <- function(jsonl_file, output_prefix = NULL, original_data = NULL, analysis_mode = "batch") {
  cat("=== 배치 결과 처리 시작 ===\n")
  
  # 결과 파싱
  final_df <- process_batch_jsonl(jsonl_file, original_data)
  
  # 03 스크립트와 동일한 파일명 체계 (타임스탬프 포함)
  if (is.null(output_prefix)) {
    # 배치 ID에서 정보 추출 시도
    batch_id <- gsub("batch_results_([^_]+)_.*", "\\1", basename(jsonl_file))
    item_count <- nrow(final_df)
    
    # 새로운 파일명 생성 함수 사용
    rds_file <- generate_filepath(analysis_mode, item_count, ".RDS", is_batch = TRUE)
    csv_file <- generate_filepath(analysis_mode, item_count, ".csv", is_batch = TRUE)
  } else {
    rds_file <- paste0(output_prefix, ".RDS")  
    csv_file <- paste0(output_prefix, ".csv")
  }
  
  saveRDS(final_df, rds_file)
  readr::write_excel_csv(final_df, csv_file, na = "")
  
  cat(sprintf("💾 결과 저장:\n"))
  cat(sprintf("   - RDS: %s\n", basename(rds_file)))
  cat(sprintf("   - CSV: %s\n", basename(csv_file)))
  
  # 분석 이력 등록 (03 스크립트와 통합)
  tryCatch({
    # 절대 경로로 확실하게 로드
    tracker_file <- "C:/Users/rubat/SynologyDrive/R project/emotion_analysis/analysis_tracker.R"
    
    if (file.exists(tracker_file)) {
      source(tracker_file, local = TRUE)
      cat("✅ analysis_tracker.R 로드 성공\n")
    } else {
      stop("analysis_tracker.R 파일을 찾을 수 없습니다: ", tracker_file)
    }
    
    tracker <- AnalysisTracker$new()
    
    # dominant_emotion 컬럼이 있는 경우에만 필터링
    if ("dominant_emotion" %in% names(final_df)) {
      cat("🔍 필터링 전 데이터 상태 확인:\n")
      cat(sprintf("총 %d행\n", nrow(final_df)))
      
      # dominant_emotion 값 분포 확인
      emotion_counts <- table(final_df$dominant_emotion, useNA = "always")
      cat("dominant_emotion 값 분포:\n")
      print(emotion_counts)
      
      # 필터링 전 카운트
      exclude_count <- sum(final_df$dominant_emotion %in% c("분석 제외", "파싱 오류", "API 오류"), na.rm = TRUE)
      valid_count <- nrow(final_df) - exclude_count
      cat(sprintf("필터링 대상: %d개, 유효한 데이터: %d개\n", exclude_count, valid_count))
      
      if (valid_count > 0) {
        filtered_df <- final_df %>% filter(dominant_emotion != "분석 제외", dominant_emotion != "파싱 오류", dominant_emotion != "API 오류")
        cat(sprintf("✅ 필터링 완료: %d행 → %d행\n", nrow(final_df), nrow(filtered_df)))
      } else {
        cat("⚠️ 유효한 데이터가 없습니다. 전체 데이터를 등록합니다.\n")
        filtered_df <- final_df
      }
    } else {
      # dominant_emotion 컬럼이 없으면 전체 데이터 사용
      cat("⚠️ dominant_emotion 컬럼이 없습니다. 전체 데이터를 등록합니다.\n")
      filtered_df <- final_df
    }
    
    tracker$register_analysis(
      filtered_df,
      analysis_type = paste0("batch_", tolower(analysis_mode)),
      model_used = "gemini-2.5-flash", # 기본값
      analysis_file = "process_batch_results"
    )
    cat("✅ 분석 이력 등록 완료\n")
  }, error = function(e) {
    cat(sprintf("⚠️ 분석 이력 등록 실패: %s\n", e$message))
  })
  
  # 인간 코딩용 구글 시트 생성 (03 스크립트와 동일한 로직)
  should_enable_human_coding <- case_when(
    analysis_mode == "code_check" ~ FALSE,  # 코드 점검: 인간 코딩 생략
    analysis_mode == "pilot" ~ TRUE,        # 파일럿: 활성화 (크기에 따라 실행 여부 결정)
    analysis_mode == "sampling" ~ TRUE,     # 표본 분석: 필수
    analysis_mode == "full" ~ HUMAN_CODING_CONFIG$enable_human_coding,   # 전체: 설정에 따름
    analysis_mode == "batch" ~ HUMAN_CODING_CONFIG$enable_human_coding,  # 기본 배치 모드
    analysis_mode == "manual" ~ HUMAN_CODING_CONFIG$enable_human_coding, # 수동 다운로드
    TRUE ~ FALSE
  )
  
  # 모드별 최소 샘플 크기 요구사항
  min_size_for_mode <- case_when(
    analysis_mode == "pilot" ~ 20,          # 파일럿: 최소 20개
    analysis_mode == "sampling" ~ HUMAN_CODING_CONFIG$min_sample_size,  # 표본: 기본 설정
    TRUE ~ HUMAN_CODING_CONFIG$min_sample_size
  )
  
  # 파일명에서 샘플 라벨 생성
  sample_label <- sprintf("BATCH_%s_%ditems", toupper(analysis_mode), nrow(final_df))
  
  if (should_enable_human_coding && nrow(final_df) >= min_size_for_mode) {
    
    cat("📋 인간 코딩용 구글 시트 생성을 시작합니다...\n")
    
    tryCatch({
      # 성공적으로 분석된 데이터만 사용 (오류 제외)
      valid_for_coding <- final_df %>%
        filter(!is.na(dominant_emotion), 
               !dominant_emotion %in% c("API 오류", "파싱 오류", "분석 오류", "분석 제외"))
      
      cat(sprintf("📊 인간 코딩용 유효 샘플: %d개\n", nrow(valid_for_coding)))
      
      if (nrow(valid_for_coding) >= HUMAN_CODING_CONFIG$min_sample_size) {
        sheet_urls <- create_human_coding_sheets(valid_for_coding, sample_label)
        
        if (!is.null(sheet_urls) && length(sheet_urls) > 0) {
          cat(sprintf("✅ 인간 코딩용 시트 %d개가 성공적으로 생성되었습니다.\n", length(sheet_urls)))
          # 모드별 안내 메시지
          mode_guidance <- switch(analysis_mode,
            "code_check" = "🔧 배치 코드점검 인간 코딩 (생략됨)",
            "pilot" = "🧪 배치 파일럿 인간 코딩 (선택사항)",
            "sampling" = "📊 배치 표본분석 인간 코딩 (필수)",
            "full" = "🌍 배치 전체분석 인간 코딩 (표본 기반)",
            "batch" = "💰 배치 처리 인간 코딩",
            "manual" = "🔍 수동 다운로드 인간 코딩",
            "배치 결과 인간 코딩"
          )
          
          cat(sprintf("\n🎯 %s - 다음 단계:\n", mode_guidance))
          cat("1. 위에 표시된 URL을 4명의 코더에게 전달\n")
          cat("2. 각 시트 확인:\n")
          cat("   ✅ 체크박스 자동 생성 성공 → 바로 작업 시작\n")
          cat("   ⚠️  체크박스 없음 → '참고사항' 탭에서 수동 설정 방법 확인\n")
          cat("3. 코더들이 human_agree 열에서 동의/비동의 체크\n")
          cat("4. 모든 코더 완료 후 '05_신뢰도_분석.R' 실행\n")
          cat("5. Krippendorff's Alpha로 신뢰도 측정\n")
          
          if (analysis_mode == "sampling") {
            cat("\n⚠️  배치 표본분석: 인간 코딩 검증이 통계적 유의성에 중요합니다!\n")
          } else if (analysis_mode == "pilot") {
            cat("\n💡 배치 파일럿: 방법론 검증을 위한 선택적 인간 코딩입니다.\n")
          } else {
            cat(sprintf("\n💰 배치 처리 완료: %d%% 할인된 비용으로 분석이 완료되었습니다.\n", 
                        BATCH_CONFIG$cost_savings_percentage))
          }
          cat("\n")
        } else {
          cat("⚠️ 인간 코딩용 시트 생성에 실패했습니다.\n")
        }
      } else {
        cat(sprintf("📋 유효한 분석 결과(%d건)가 %s 모드 최소 요구사항(%d건)보다 적어 인간 코딩을 생략합니다.\n", 
                                   nrow(valid_for_coding), analysis_mode, min_size_for_mode))
      }
      
    }, error = function(e) {
      cat(sprintf("❌ 인간 코딩 시트 생성 중 오류: %s\n", e$message))
      cat("📋 구글 시트 생성에 실패했지만 분석 결과는 정상적으로 저장되었습니다.\n")
    })
  } else {
    # 인간 코딩이 활성화되지 않은 경우의 안내
    if (!should_enable_human_coding) {
      mode_reason <- switch(analysis_mode,
        "code_check" = "배치 코드점검 모드는 인간 코딩을 생략합니다",
        "full" = "배치 전체분석 모드에서 인간 코딩이 비활성화되었습니다",
        "기본 설정에 의해 인간 코딩이 비활성화되었습니다"
      )
      cat(sprintf("📋 %s.\n", mode_reason))
    } else if (nrow(final_df) < min_size_for_mode) {
      cat(sprintf("📋 분석 결과(%d건)가 %s 모드 최소 요구사항(%d건)보다 적어 인간 코딩을 생략합니다.\n", 
                                 nrow(final_df), analysis_mode, min_size_for_mode))
    }
  }
  
  # 요약 통계
  cat("\n📈 분석 결과 요약:\n")
  if ("dominant_emotion" %in% names(final_df)) {
    emotion_summary <- final_df %>%
      count(dominant_emotion, sort = TRUE)
    print(emotion_summary)
  }
  
  cat("=== 배치 결과 처리 완료 ===\n")
  return(final_df)
}

# 사용 예시
if (!interactive()) {
  # 스크립트 직접 실행 시
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 0) {
    jsonl_file <- args[1]
    result <- process_completed_batch(jsonl_file)
  } else {
    cat("사용법: Rscript process_batch_results.R <jsonl_file>\n")
  }
}