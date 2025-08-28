# 배치 결과 처리 테스트 스크립트
library(arrow)
library(dplyr)

# 진단 로그 분석
cat("=== 배치 처리 문제 진단 ===\n\n")

# 1. 로그 분석
log_lines <- readLines("results/current_batch_jobs.txt")
cat("배치 작업 목록:\n")
cat(paste(log_lines, collapse = "\n"), "\n\n")

# 2. 배치 원시 데이터 확인
raw_files <- list.files("results", pattern = "batch_raw_.*\\.jsonl$", full.names = TRUE)
if (length(raw_files) > 0) {
  cat("원시 배치 파일들:\n")
  for (file in raw_files) {
    cat("  -", basename(file), "\n")
  }
  
  # 가장 최근 파일 확인
  latest_raw <- raw_files[length(raw_files)]
  cat("\n가장 최근 원시 파일:", basename(latest_raw), "\n")
  
  # 파일 내용 확인
  lines <- readLines(latest_raw)
  cat("라인 수:", length(lines), "\n")
}

# 3. 파싱된 배치 데이터 확인
parsed_files <- list.files("results", pattern = "batch_parsed_.*\\.(RDS|parquet)$", full.names = TRUE)
if (length(parsed_files) > 0) {
  cat("\n파싱된 배치 파일들:\n")
  for (file in parsed_files) {
    cat("  -", basename(file), "\n")
  }
  
  # RDS 파일 로드 시도
  rds_files <- parsed_files[grepl("\\.RDS$", parsed_files)]
  if (length(rds_files) > 0) {
    latest_rds <- rds_files[length(rds_files)]
    cat("\nRDS 파일 로드 시도:", basename(latest_rds), "\n")
    
    tryCatch({
      batch_data <- readRDS(latest_rds)
      cat("로드 성공: ", length(batch_data), "개 항목\n")
      
      if (length(batch_data) > 0) {
        first_item <- batch_data[[1]]
        cat("첫 항목 구조:\n")
        str(first_item)
        
        if (!is.null(first_item$key)) {
          cat("Key:", first_item$key, "\n")
        }
      }
    }, error = function(e) {
      cat("로드 실패:", e$message, "\n")
    })
  }
}

cat("\n=== 진단 완료 ===\n")