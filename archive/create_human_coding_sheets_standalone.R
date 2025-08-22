# 독립 실행 인간 코딩 시트 생성 스크립트
# 기존 분석 결과를 사용하여 구글 시트 생성

# 설정 및 유틸리티 로드
source("config.R")
source("utils.R")
source("human_coding.R")

# 필요한 패키지 로드
required_packages <- c("dplyr", "googlesheets4", "googledrive", "readr")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)

# 구글 인증 설정
cat("=== 구글 시트 인증 확인 ===\n")
if (!gs4_has_token()) {
  cat("구글 시트 인증이 필요합니다. 브라우저가 열리면 계정을 선택하고 권한을 허용해주세요.\n")
  gs4_auth(email = TRUE)
  
  if (!gs4_has_token()) {
    stop("구글 시트 인증에 실패했습니다. gs4_auth(email = TRUE)를 다시 실행해주세요.")
  }
} else {
  cat("기존 구글 시트 인증을 사용합니다.\n")
}

# 구글 드라이브 인증도 설정
if (!drive_has_token()) {
  drive_auth(token = gs4_token())
}

cat("✅ 구글 인증 완료\n\n")

# 사용 가능한 분석 결과 파일 목록 표시
cat("=== 사용 가능한 분석 결과 파일 ===\n")
result_files <- list.files("results", pattern = "analysis_results.*\\.RDS$", full.names = TRUE)
result_files <- result_files[!grepl("_rerun", basename(result_files))]  # 재분석 파일 제외

for (i in seq_along(result_files)) {
  file_info <- file.info(result_files[i])
  file_size <- nrow(readRDS(result_files[i]))
  cat(sprintf("%d. %s (%d개 항목, %s)\n", 
              i, 
              basename(result_files[i]), 
              file_size,
              format(file_info$mtime, "%Y-%m-%d %H:%M")))
}

# 사용자 선택 받기
cat("\n어떤 분석 결과로 인간 코딩 시트를 생성하시겠습니까?\n")
cat("번호를 입력하세요 (예: 1): ")
selection <- as.numeric(readline())

if (is.na(selection) || selection < 1 || selection > length(result_files)) {
  stop("올바른 번호를 선택해주세요.")
}

selected_file <- result_files[selection]
cat(sprintf("\n선택된 파일: %s\n", basename(selected_file)))

# 분석 결과 로드
analysis_results <- readRDS(selected_file)
cat(sprintf("로드된 데이터: %d행 × %d열\n", nrow(analysis_results), ncol(analysis_results)))

# 파일명에서 샘플 라벨 추출
file_basename <- basename(selected_file)
if (grepl("CODE_CHECK", file_basename)) {
  sample_label <- gsub(".*_(CODE_CHECK_\\d+items).*", "\\1", file_basename)
  cat("⚠️  CODE_CHECK 모드는 일반적으로 인간 코딩을 생략합니다. 계속 진행하시겠습니까? (y/n): ")
  continue_choice <- readline()
  if (tolower(continue_choice) != "y") {
    stop("사용자가 중단을 선택했습니다.")
  }
} else if (grepl("PILOT", file_basename)) {
  sample_label <- gsub(".*_(PILOT_\\d+items).*", "\\1", file_basename)
} else if (grepl("SAMPLING", file_basename)) {
  sample_label <- gsub(".*_(SAMPLING_\\d+items).*", "\\1", file_basename)
} else if (grepl("ADAPTIVE", file_basename)) {
  sample_label <- gsub(".*_(ADAPTIVE_\\d+items).*", "\\1", file_basename)
} else if (grepl("SAMPLE", file_basename)) {
  sample_label <- gsub(".*_(SAMPLE_\\d+posts).*", "\\1", file_basename)
} else if (grepl("FULL", file_basename)) {
  sample_label <- "FULL"
} else {
  sample_label <- sprintf("CUSTOM_%ditems", nrow(analysis_results))
}

cat(sprintf("추출된 샘플 라벨: %s\n", sample_label))

# 유효한 데이터 필터링 (분석 성공한 항목만)
valid_data <- analysis_results %>%
  filter(!is.na(dominant_emotion), 
         !dominant_emotion %in% c("API 오류", "파싱 오류", "분석 오류", "분석 제외"))

cat(sprintf("인간 코딩 대상: %d개 (전체 %d개 중)\n", nrow(valid_data), nrow(analysis_results)))

# 최소 샘플 크기 확인
min_required <- HUMAN_CODING_CONFIG$min_sample_size
if (nrow(valid_data) < min_required) {
  cat(sprintf("⚠️  유효한 데이터(%d개)가 최소 요구사항(%d개)보다 적습니다.\n", 
              nrow(valid_data), min_required))
  cat("그래도 계속 진행하시겠습니까? (y/n): ")
  continue_choice <- readline()
  if (tolower(continue_choice) != "y") {
    stop("사용자가 중단을 선택했습니다.")
  }
}

# 인간 코딩 시트 생성
cat("\n=== 인간 코딩 시트 생성 시작 ===\n")
log_message("INFO", sprintf("독립 실행으로 %s 데이터의 인간 코딩 시트를 생성합니다.", sample_label))

tryCatch({
  sheet_urls <- create_human_coding_sheets(valid_data, sample_label)
  
  if (!is.null(sheet_urls) && length(sheet_urls) > 0) {
    cat("\n🎯 인간 코딩 시트 생성이 완료되었습니다!\n")
    cat("\n=== 생성된 시트 URL ===\n")
    for (i in 1:length(sheet_urls)) {
      coder_name <- names(sheet_urls)[i]
      url <- sheet_urls[[i]]
      cat(sprintf("%s: %s\n", coder_name, url))
    }
    
    cat("\n📋 다음 단계:\n")
    cat("1. 위 URL을 각 코더에게 전달\n")
    cat("2. 코더들이 human_agree 열에서 체크박스로 동의/비동의 표시\n")
    cat("3. 모든 코더 완료 후 '05_신뢰도_분석.R' 실행\n")
    
    log_message("INFO", sprintf("인간 코딩 시트 %d개 생성 완료", length(sheet_urls)))
    
  } else {
    cat("❌ 인간 코딩 시트 생성에 실패했습니다.\n")
    log_message("ERROR", "인간 코딩 시트 생성 실패")
  }
  
}, error = function(e) {
  cat(sprintf("❌ 오류 발생: %s\n", e$message))
  log_message("ERROR", sprintf("독립 실행 중 오류: %s", e$message))
})

cat("\n=== 독립 실행 완료 ===\n")