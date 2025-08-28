# 기존 분석 결과를 인간 코딩 시트로 내보내기 테스트
# 목적: primary_target 필드가 포함된 기존 분석 결과를 인간 코딩 시트로 생성

# 초기화 시스템 로드
source("libs/init.R")

# 필수 모듈 로드
suppressMessages({
  if (!requireNamespace("googlesheets4", quietly = TRUE)) install.packages("googlesheets4")
  if (!requireNamespace("googledrive", quietly = TRUE)) install.packages("googledrive")
  library(googlesheets4, quietly = TRUE)
  library(googledrive, quietly = TRUE)
  library(dplyr, quietly = TRUE)
})

source("libs/utils.R")
source("modules/human_coding.R")

# 기존 분석 결과 로드
parquet_file <- "results/analysis_results_pilot_20250827_213302.parquet"

if (!file.exists(parquet_file)) {
  stop(paste("파일을 찾을 수 없습니다:", parquet_file))
}

cat("=== 기존 분석 결과 내보내기 테스트 ===\n")
cat("파일:", parquet_file, "\n")

# Parquet 파일 로드
tryCatch({
  library(arrow, quietly = TRUE)
  analysis_results <- read_parquet(parquet_file)
  cat("✅ Parquet 파일 로드 성공\n")
  cat("   - 총 행 수:", nrow(analysis_results), "\n")
  cat("   - 총 열 수:", ncol(analysis_results), "\n")
}, error = function(e) {
  cat("❌ Parquet 로드 실패, RDS 방식으로 시도...\n")
  # RDS 대안이 있다면 시도
  rds_file <- gsub("\\.parquet$", ".RDS", parquet_file)
  if (file.exists(rds_file)) {
    analysis_results <- readRDS(rds_file)
    cat("✅ RDS 파일 로드 성공\n")
  } else {
    stop("Parquet과 RDS 파일 모두 로드 실패")
  }
})

# 컬럼 구조 확인
cat("\n=== 데이터 구조 확인 ===\n")
cat("컬럼명:\n")
print(names(analysis_results))

# primary_target 필드 존재 확인
if ("primary_target" %in% names(analysis_results)) {
  cat("\n✅ primary_target 필드 발견!\n")
  cat("Primary Target 분포:\n")
  print(table(analysis_results$primary_target, useNA = "always"))
} else {
  cat("\n❌ primary_target 필드가 없습니다.\n")
  cat("사용 가능한 감정 관련 필드:\n")
  emotion_cols <- names(analysis_results)[grepl("emotion|target|감정", names(analysis_results), ignore.case = TRUE)]
  print(emotion_cols)
}

# 샘플 데이터 확인 (처음 3행)
cat("\n=== 샘플 데이터 (처음 3행) ===\n")
if (nrow(analysis_results) > 0) {
  sample_data <- analysis_results[1:min(3, nrow(analysis_results)), ]
  
  # 주요 필드만 출력
  key_cols <- intersect(names(sample_data), 
                       c("post_id", "comment_id", "content", "combinated_emotion", 
                         "complex_emotion", "primary_target", "기쁨", "신뢰", "P", "A", "D"))
  
  if (length(key_cols) > 0) {
    print(sample_data[, key_cols])
  } else {
    print(sample_data[, 1:min(5, ncol(sample_data))])
  }
}

# 인간 코딩 시트 생성 테스트 (소규모 샘플)
cat("\n=== 인간 코딩 시트 생성 테스트 ===\n")

# 테스트용 소규모 샘플 추출 (10개 항목)
if (nrow(analysis_results) > 10) {
  set.seed(123)
  test_sample <- analysis_results %>% 
    sample_n(10) %>%
    arrange(post_id)
  cat("✅ 10개 항목 샘플링 완료\n")
} else {
  test_sample <- analysis_results
  cat("✅ 전체 데이터 사용 (10개 이하)\n")
}

cat("샘플 크기:", nrow(test_sample), "행\n")

# 인간 코딩 시트 생성 시도
cat("\n📋 인간 코딩 시트 생성 시작...\n")

tryCatch({
  sheet_urls <- create_human_coding_sheets(
    analysis_results = test_sample,
    sample_label = "PILOT_PRIMARY_TARGET_TEST"
  )
  
  if (!is.null(sheet_urls) && length(sheet_urls) > 0) {
    cat("\n🎉 인간 코딩 시트 생성 성공!\n")
    cat("생성된 시트 수:", length(sheet_urls), "\n")
    
    cat("\n=== 생성된 시트 URL ===\n")
    for (coder in names(sheet_urls)) {
      cat(sprintf("%s: %s\n", coder, sheet_urls[[coder]]))
    }
    
    cat("\n✅ primary_target 필드가 포함된 시트 생성 완료\n")
    cat("🔍 시트를 열어서 다음 항목들이 포함되었는지 확인하세요:\n")
    cat("   - 플루치크 8대 감정 점수\n")
    cat("   - 조합감정 (combinated_emotion)\n")
    cat("   - PAD 점수 (P, A, D)\n")
    cat("   - 복합감정 (complex_emotion)\n")
    cat("   - 감정대상 (primary_target) ← 새로 추가된 필드\n")
    cat("   - 분석근거 (rationale)\n")
    cat("   - 인간 동의 체크박스 (human_agree)\n")
    
  } else {
    cat("\n⚠️ 구글 시트 생성 실패, 로컬 CSV 파일 확인\n")
    
    # 로컬 파일 확인
    local_dir <- "results/human_coding_local"
    if (dir.exists(local_dir)) {
      local_files <- list.files(local_dir, pattern = "PILOT_PRIMARY_TARGET_TEST.*\\.csv$", full.names = TRUE)
      if (length(local_files) > 0) {
        cat("📁 생성된 로컬 CSV 파일들:\n")
        for (file in local_files) {
          cat("   -", basename(file), "\n")
        }
        
        # 첫 번째 파일의 구조 확인
        if (file.exists(local_files[1])) {
          test_csv <- read.csv(local_files[1], stringsAsFactors = FALSE, fileEncoding = "UTF-8")
          cat("\n📊 CSV 파일 구조 확인:\n")
          cat("   컬럼 수:", ncol(test_csv), "\n")
          cat("   행 수:", nrow(test_csv), "\n")
          cat("   컬럼명:", paste(names(test_csv), collapse = ", "), "\n")
          
          if ("primary_target" %in% names(test_csv)) {
            cat("   ✅ primary_target 필드 포함됨\n")
          } else {
            cat("   ❌ primary_target 필드 누락\n")
          }
        }
      } else {
        cat("❌ 로컬 CSV 파일도 생성되지 않았습니다.\n")
      }
    }
  }
  
}, error = function(e) {
  cat("\n❌ 인간 코딩 시트 생성 중 오류 발생:\n")
  cat("오류 내용:", e$message, "\n")
  
  # 수동 내보내기 시도
  cat("\n🔄 수동 CSV 내보내기 시도...\n")
  
  tryCatch({
    # 수동으로 CSV 파일 생성
    output_file <- paste0("results/manual_export_pilot_primary_target_test_", 
                         format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")
    
    # 필요한 컬럼만 선택해서 내보내기
    export_cols <- intersect(names(test_sample), 
                            c("post_id", "comment_id", "content", 
                              "기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대",
                              "combinated_emotion", "P", "A", "D", "complex_emotion", 
                              "primary_target", "rationale"))
    
    if (length(export_cols) > 0) {
      export_data <- test_sample[, export_cols] %>%
        mutate(human_agree = FALSE)  # 체크박스 컬럼 추가
      
      write.csv(export_data, output_file, row.names = FALSE, fileEncoding = "UTF-8")
      cat("✅ 수동 CSV 내보내기 성공:\n")
      cat("   파일:", output_file, "\n")
      cat("   컬럼 수:", ncol(export_data), "\n")
      cat("   primary_target 포함:", "primary_target" %in% names(export_data), "\n")
    } else {
      cat("❌ 내보낼 컬럼을 찾을 수 없습니다.\n")
    }
    
  }, error = function(e2) {
    cat("❌ 수동 내보내기도 실패:", e2$message, "\n")
  })
})

cat("\n=== 테스트 완료 ===\n")