# 유틸리티 함수들

# 로깅 함수
log_message <- function(level = "INFO", message, timestamp = TRUE) {
  if (!LOG_CONFIG$enable_logging) return(invisible(NULL))
  
  # 로그 레벨 체크
  levels <- c("DEBUG" = 1, "INFO" = 2, "WARN" = 3, "ERROR" = 4)
  if (levels[[level]] < levels[[LOG_CONFIG$log_level]]) return(invisible(NULL))
  
  # 로그 디렉토리 생성
  if (!dir.exists("logs")) dir.create("logs", recursive = TRUE)
  
  # 타임스탬프 추가
  time_str <- if (timestamp) paste0("[", Sys.time(), "] ") else ""
  log_entry <- paste0(time_str, "[", level, "] ", message)
  
  # 콘솔 출력 (색상 적용 - crayon 패키지 있는 경우만)
  if (require("crayon", quietly = TRUE)) {
    if (level == "ERROR") {
      cat(crayon::red(log_entry), "\n")
    } else if (level == "WARN") {
      cat(crayon::yellow(log_entry), "\n")
    } else if (level == "INFO") {
      cat(crayon::green(log_entry), "\n")
    } else {
      cat(log_entry, "\n")
    }
  } else {
    # crayon 패키지가 없는 경우 기본 출력
    cat(log_entry, "\n")
  }
  
  # 파일 기록
  write(log_entry, file = LOG_CONFIG$log_file, append = TRUE)
}

# 진행상황 추적 함수 제거됨 (사용하지 않음)

# 체크포인트 저장
save_checkpoint <- function(data, checkpoint_name, script_name) {
  checkpoint_dir <- "checkpoints"
  if (!dir.exists(checkpoint_dir)) dir.create(checkpoint_dir, recursive = TRUE)
  
  checkpoint_file <- file.path(checkpoint_dir, paste0(script_name, "_", checkpoint_name, ".RDS"))
  save_checkpoint(data, basename(gsub("\\.RDS$", "", checkpoint_file)))
  
  log_message("INFO", sprintf("체크포인트 저장: %s", checkpoint_file))
  return(checkpoint_file)
}

# 체크포인트 로드
load_checkpoint <- function(checkpoint_name, script_name) {
  checkpoint_file <- file.path("checkpoints", paste0(script_name, "_", checkpoint_name, ".RDS"))
  
  if (file.exists(checkpoint_file)) {
    log_message("INFO", sprintf("체크포인트 로드: %s", checkpoint_file))
    return(load_checkpoint(basename(gsub("\\.RDS$", "", checkpoint_file))))
  }
  
  log_message("WARN", sprintf("체크포인트 파일 없음: %s", checkpoint_file))
  return(NULL)
}

# 데이터 검증
validate_data <- function(data, required_columns = NULL, min_rows = 1) {
  if (is.null(data) || nrow(data) < min_rows) {
    log_message("ERROR", sprintf("데이터 검증 실패: 최소 %d행 필요, 현재 %d행", min_rows, nrow(data)))
    return(FALSE)
  }
  
  if (!is.null(required_columns)) {
    missing_cols <- setdiff(required_columns, names(data))
    if (length(missing_cols) > 0) {
      log_message("ERROR", sprintf("필수 컬럼 누락: %s", paste(missing_cols, collapse = ", ")))
      return(FALSE)
    }
  }
  
  log_message("INFO", sprintf("데이터 검증 완료: %d행, %d컬럼", nrow(data), ncol(data)))
  return(TRUE)
}

# 실행 시간 측정
time_execution <- function(expr, description = "") {
  start_time <- Sys.time()
  result <- expr
  elapsed <- difftime(Sys.time(), start_time, units = "secs")
  
  if (description != "") {
    log_message("INFO", sprintf("%s 실행시간: %.2f초", description, elapsed))
  }
  
  return(result)
}

# Null-coalescing operator (R 기본 제공 안됨)
`%||%` <- function(lhs, rhs) {
  if (!is.null(lhs) && length(lhs) > 0 && !is.na(lhs)) lhs else rhs
}

# 게시물 단위로 샘플 크기 조정 함수 (분석 전 확정용)
adjust_sample_size_by_posts <- function(sample_data, target_size) {
  
  # 각 게시물별 샘플 개수 계산
  post_sample_counts <- sample_data %>%
    count(post_id, name = "post_samples") %>%
    arrange(desc(post_samples))
  
  log_message("INFO", sprintf("현재 %d개 게시물, 평균 %.1f개/게시물", 
                              nrow(post_sample_counts), 
                              mean(post_sample_counts$post_samples)))
  
  # 목표 크기에 맞도록 게시물 선택 (욕심쟁이 알고리즘)
  selected_posts <- c()
  current_total <- 0
  
  for (i in 1:nrow(post_sample_counts)) {
    post_id <- post_sample_counts$post_id[i]
    post_count <- post_sample_counts$post_samples[i]
    
    # 이 게시물을 추가해도 목표를 크게 초과하지 않으면 추가
    if (current_total + post_count <= target_size * 1.1) {  # 10% 여유
      selected_posts <- c(selected_posts, post_id)
      current_total <- current_total + post_count
    }
    
    # 목표에 도달하면 중단
    if (current_total >= target_size) {
      break
    }
  }
  
  # 선택된 게시물들의 모든 데이터 추출
  adjusted_sample <- sample_data %>%
    filter(post_id %in% selected_posts) %>%
    arrange(post_id, if("comment_id" %in% names(.)) comment_id else NULL)
  
  log_message("INFO", sprintf("게시물 기반 조정: %d개 게시물 선택, 최종 %d개 샘플", 
                              length(selected_posts), nrow(adjusted_sample)))
  
  return(adjusted_sample)
}

# 파일명 생성 함수 (타임스탬프 포함 옵션)
generate_filename <- function(base_name, mode, item_count, file_ext = ".RDS", is_batch = FALSE) {
  # 기본 라벨 생성
  mode_prefix <- if (is_batch) "BATCH_" else ""
  base_label <- sprintf("_%s%s_%ditems", mode_prefix, toupper(mode), item_count)
  
  # 타임스탬프 추가 여부 확인
  if (FILE_CONFIG$include_timestamp) {
    timestamp <- format(Sys.time(), FILE_CONFIG$timestamp_format)
    final_label <- sprintf("%s%s%s", base_label, FILE_CONFIG$timestamp_separator, timestamp)
  } else {
    final_label <- base_label
  }
  
  return(paste0(base_name, final_label, file_ext))
}

# 파일 경로 생성 함수
generate_filepath <- function(mode, item_count, file_ext = ".RDS", is_batch = FALSE) {
  filename <- generate_filename("analysis_results", mode, item_count, file_ext, is_batch)
  return(file.path(PATHS$results_dir, filename))
}

# 간소화된 분석 모드 선택 함수 (배치 옵션 제외)
get_analysis_mode_simple <- function() {
  cat("\n", rep("=", 70), "\n")
  cat("🔬 감정분석 실행 모드 선택\n")
  cat(rep("=", 70), "\n")
  cat("1️⃣  코드 점검 (Code Check) - 1개 게시물 테스트\n")
  cat("2️⃣  파일럿 연구 (Pilot Study) - 5개 게시물 예비 분석\n")
  cat("3️⃣  표본 분석 (Sampling Analysis) - 384개 이상 통계적 분석\n")
  cat("4️⃣  전체 분석 (Full Analysis) - 모든 데이터 분석\n")
  cat("\n")
  cat("💰 배치 처리가 필요하면 04_batch_emotion_analysis.R을 실행하세요\n")
  cat("\n선택하세요 (1-4): ")
  
  while (TRUE) {
    choice <- readline()
    
    if (choice == "1") {
      cat("🔧 코드 점검 모드 선택됨\n")
      return("code_check")
    } else if (choice == "2") {
      cat("🧪 파일럿 연구 모드 선택됨\n")
      return("pilot")
    } else if (choice == "3") {
      cat("📊 표본 분석 모드 선택됨\n")
      return("sampling")
    } else if (choice == "4") {
      confirm <- readline("⚠️  전체 분석은 시간과 비용이 매우 많이 듭니다. 계속하시겠습니까? (y/N): ")
      if (tolower(confirm) %in% c("y", "yes", "ㅇ")) {
        cat("🌍 전체 분석 모드 선택됨\n")
        return("full")
      } else {
        cat("❌ 전체 분석이 취소되었습니다. 다시 선택해주세요.\n\n")
      }
    } else if (tolower(choice) %in% c("b", "batch", "배치")) {
      cat("💡 배치 처리 옵션으로 이동하려면 이 스크립트를 종료하고\n")
      cat("   04_batch_emotion_analysis.R을 실행하세요.\n")
      return("batch_processing")
    } else {
      cat("❌ 잘못된 선택입니다. 1-4 중에서 선택해주세요.\n")
    }
  }
}