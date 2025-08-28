# 프로젝트 통합 초기화 시스템 - Parquet 전용
# Apache Parquet 형식으로 완전 일원화

# =============================================================================
# 패키지 관리 및 로딩
# =============================================================================

# 필수 패키지 설치 및 로딩
suppressMessages({
  # 기존 필수 패키지
  if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
  if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
  if (!requireNamespace("gemini.R", quietly = TRUE)) install.packages("gemini.R")
  
  # Parquet 지원을 위한 arrow 패키지 (선택적)
  PARQUET_AVAILABLE <- FALSE
  tryCatch({
    if (!requireNamespace("arrow", quietly = TRUE)) {
      cat("📦 Installing arrow package for Parquet support...\n")
      install.packages("arrow", repos = "https://cran.rstudio.com/")
    }
    library(arrow, quietly = TRUE)
    PARQUET_AVAILABLE <- TRUE
    cat("✅ Parquet support enabled with arrow package\n")
  }, error = function(e) {
    cat("⚠️ Arrow package unavailable, using RDS fallback\n")
    PARQUET_AVAILABLE <<- FALSE
  })
  
  # 기본 패키지 로딩
  library(jsonlite, quietly = TRUE)
  library(dplyr, quietly = TRUE)
  library(gemini.R, quietly = TRUE)
})

# =============================================================================
# 설정 로드
# =============================================================================
source("libs/config.R")
source("libs/functions.R")

# =============================================================================
# Parquet 전용 I/O 함수
# =============================================================================

# 데이터 저장 함수 (Parquet 우선, RDS 대안)
save_parquet <- function(data, file_path, compression = "snappy") {
  # 디렉토리 확인 및 생성
  dir_path <- dirname(file_path)
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE)
  }
  
  if (exists("PARQUET_AVAILABLE") && PARQUET_AVAILABLE) {
    # Parquet 사용 가능시
    if (!grepl("\\.parquet$", file_path)) {
      file_path <- paste0(file_path, ".parquet")
    }
    
    tryCatch({
      arrow::write_parquet(data, file_path, compression = compression)
      cat("✅ Parquet saved:", file_path, "\n")
      return(file_path)
    }, error = function(e) {
      cat("⚠️ Parquet save failed, falling back to RDS\n")
      # Fallback to RDS
      rds_path <- gsub("\\.parquet$", ".RDS", file_path)
      saveRDS(data, rds_path, compress = TRUE)
      cat("✅ RDS saved (fallback):", rds_path, "\n")
      return(rds_path)
    })
  } else {
    # RDS fallback
    if (!grepl("\\.RDS$", file_path)) {
      file_path <- paste0(file_path, ".RDS")
    }
    
    tryCatch({
      saveRDS(data, file_path, compress = TRUE)
      cat("✅ RDS saved:", file_path, "\n")
      return(file_path)
    }, error = function(e) {
      cat("❌ Error saving RDS file:", e$message, "\n")
      return(NULL)
    })
  }
}

# 데이터 로드 함수 (Parquet 전용으로 단순화)
load_parquet <- function(file_path) {
  # .parquet 확장자 확인 및 추가
  parquet_path <- if (grepl("\\.parquet$", file_path)) file_path else paste0(file_path, ".parquet")

  # 파일 존재 여부 확인
  if (!file.exists(parquet_path)) {
    stop(sprintf("❌ Parquet 파일을 찾을 수 없습니다: %s", parquet_path))
  }

  # Parquet 패키지 가용성 확인
  if (!exists("PARQUET_AVAILABLE") || !PARQUET_AVAILABLE) {
    stop("❌ arrow 패키지가 로드되지 않아 Parquet 파일을 읽을 수 없습니다. 패키지 설치를 확인하세요.")
  }

  # 파일 읽기
  tryCatch({
    data <- arrow::read_parquet(parquet_path)
    cat("✅ Parquet loaded:", parquet_path, "| Rows:", nrow(data), "| Cols:", ncol(data), "\n")
    return(data)
  }, error = function(e) {
    stop(sprintf("❌ Parquet 파일 읽기 실패: %s. 오류: %s", parquet_path, e$message))
  })
}

# 기존 형식을 Parquet으로 변환 (마이그레이션 용도)
migrate_to_parquet <- function(old_path, remove_original = TRUE) {
  # 파일 확장자별로 처리
  if (file.exists(old_path)) {
    # 확장자 확인
    ext <- tools::file_ext(old_path)
    base_name <- tools::file_path_sans_ext(old_path)
    parquet_path <- paste0(base_name, ".parquet")
    
    tryCatch({
      data <- switch(tolower(ext),
        "rds" = readRDS(old_path),
        "csv" = read.csv(old_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8"),
        stop("Unsupported file format: ", ext)
      )
      
      # Parquet으로 저장
      arrow::write_parquet(data, parquet_path, compression = "snappy")
      cat("🔄 Migrated", ext, "to Parquet:", parquet_path, "\n")
      
      if (remove_original) {
        file.remove(old_path)
        cat("🗑️ Removed original", ext, "file\n")
      }
      
      return(parquet_path)
    }, error = function(e) {
      cat("❌ Migration failed:", e$message, "\n")
      return(NULL)
    })
  } else {
    cat("❌ File not found:", old_path, "\n")
    return(NULL)
  }
}

# 프로젝트별 데이터 로더 (기존 PATHS와 호환)
load_prompts_data <- function() {
  return(load_parquet("data/prompts_ready"))
}

# 결과 저장 함수 (기존 스크립트와 호환)
save_analysis_results <- function(data, mode = "", timestamp = TRUE) {
  if (timestamp) {
    time_suffix <- format(Sys.time(), "_%Y%m%d_%H%M%S")
  } else {
    time_suffix <- ""
  }
  
  mode_suffix <- if (mode != "") paste0("_", mode) else ""
  file_path <- paste0("results/analysis_results", mode_suffix, time_suffix)
  
  return(save_parquet(data, file_path))
}

# 체크포인트 저장/로드 함수
save_checkpoint <- function(data, checkpoint_name) {
  file_path <- paste0("checkpoints/", checkpoint_name)
  return(save_parquet(data, file_path))
}

load_checkpoint <- function(checkpoint_name) {
  file_path <- paste0("checkpoints/", checkpoint_name)
  return(load_parquet(file_path))
}

# 인간 코딩 시트 저장 (Parquet으로 변경)
save_human_coding_sheet <- function(data, sheet_name, timestamp = TRUE) {
  if (timestamp) {
    time_suffix <- format(Sys.time(), "_%Y%m%d_%H%M%S")
  } else {
    time_suffix <- ""
  }
  
  file_path <- paste0("human_coding/", sheet_name, time_suffix)
  return(save_parquet(data, file_path))
}

# =============================================================================
# 초기화 메시지
# =============================================================================
cat("🚀 Emotion Analysis Project - Enhanced I/O System\n")
if (exists("PARQUET_AVAILABLE") && PARQUET_AVAILABLE) {
  cat("   📦 Apache Parquet format with Snappy compression\n")
  cat("   ⚡ High performance columnar storage\n")
  cat("   🗜️ Reduced storage footprint\n")
} else {
  cat("   📦 RDS format (fallback mode)\n")
  cat("   ⚡ Compressed R native format\n")
  cat("   🔄 Parquet upgrade available with arrow package\n")
}
cat("   🔧 Ready for production use\n\n")