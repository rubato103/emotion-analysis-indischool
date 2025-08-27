# 인간 코더 신뢰도 분석 시스템
# Krippendorff's Alpha 계산 및 리포트 생성

# 필요한 패키지 및 함수 로드
source("libs/config.R")
source("libs/utils.R")
source("modules/human_coding.R")
source("additional_reliability_functions.R")

required_packages <- c("dplyr", "googlesheets4", "readr", "irr")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages, dependencies = TRUE)
}
lapply(required_packages, library, character.only = TRUE)

log_message("INFO", "=== 인간 코더 신뢰도 분석 시작 ===")

# 구글 시트에서 인간 코딩 결과 읽기
cat("📊 구글 시트에서 인간 코딩 결과를 분석합니다.\n")
cat("💡 인간 코더들이 구글 시트에서 작업을 완료했는지 확인하세요!\n\n")

# results/ 폴더에서 human_coding_info_*.csv 파일 검색
info_files <- list.files("results", pattern = "human_coding_info_.*\\.csv", full.names = TRUE)
if (length(info_files) == 0) {
  stop("❌ 인간 코딩 정보 파일을 찾을 수 없습니다. 먼저 03_full_emotion_analysis.R을 실행하여 인간 코딩용 시트를 생성하세요.")
}

cat("📁 발견된 인간 코딩 정보 파일:\n")
for (i in seq_along(info_files)) {
  file_info <- basename(info_files[i])
  cat(sprintf("  %d. %s\n", i, file_info))
}

cat("\n선택할 파일 번호를 입력하세요 (기본값: 1): ")
user_input <- readline()
user_choice <- suppressWarnings(as.integer(user_input))
if (is.na(user_choice) || user_choice < 1 || user_choice > length(info_files)) {
  user_choice <- 1
  cat("기본값(1)을 사용합니다.\n")
}

selected_info_file <- info_files[user_choice]
log_message("INFO", sprintf("선택된 파일: %s", basename(selected_info_file)))

# 시트 정보 로드
sheet_info <- read.csv(selected_info_file, stringsAsFactors = FALSE)
log_message("INFO", sprintf("로드된 시트 정보: %d개 코더", nrow(sheet_info)))

# 구글 시트 인증 설정
cat("\n🔐 구글 시트 인증을 진행합니다...\n")
tryCatch({
  # 기존 인증 해제 후 새로 인증
  gs4_deauth()
  gs4_auth(email = TRUE)
  log_message("INFO", "구글 시트 인증 완료")
}, error = function(e) {
  log_message("ERROR", sprintf("구글 시트 인증 실패: %s", e$message))
  cat("❌ 구글 시트 인증에 실패했습니다.\n")
  cat("💡 해결 방법:\n")
  cat("  1. 인터넷 연결 확인\n")
  cat("  2. 구글 계정 로그인 상태 확인\n")
  cat("  3. R 세션 재시작 후 다시 시도\n")
  stop("구글 시트 접근을 위해 인증이 필요합니다.")
})

# 각 코더의 데이터 수집
cat("\n📊 각 코더의 구글 시트에서 데이터를 수집합니다...\n")
coder_data_list <- list()
failed_coders <- c()

for (i in 1:nrow(sheet_info)) {
  coder_name <- sheet_info$coder[i]
  sheet_url <- sheet_info$sheet_url[i]
  
  cat(sprintf("🔄 %s (%d/%d) 데이터 수집 중...\n", coder_name, i, nrow(sheet_info)))
  log_message("INFO", sprintf("%s 데이터 수집 시작", coder_name))
  
  tryCatch({
    # 구글 시트에서 데이터 읽기
    sheet_id <- extract_sheet_id(sheet_url)
    if (is.null(sheet_id)) {
      stop(sprintf("시트 URL에서 ID 추출 실패: %s", sheet_url))
    }
    
    raw_data <- read_sheet(sheet_id, sheet = "coding_data")
    log_message("INFO", sprintf("%s 원시 데이터 로드: %d행 × %d열", coder_name, nrow(raw_data), ncol(raw_data)))
    
    # --- START of new robust logic ---
    # 1. Create unique_id
    if (!"post_id" %in% names(raw_data)) {
        stop("필수 컬럼 'post_id'를 찾을 수 없습니다.")
    }
    raw_data$unique_id <- as.character(raw_data$post_id)
    if ("comment_id" %in% names(raw_data)) {
        comment_rows <- !is.na(raw_data$comment_id) & raw_data$comment_id != ""
        raw_data$unique_id[comment_rows] <- paste(raw_data$post_id[comment_rows], raw_data$comment_id[comment_rows], sep = "_")
    }

    # 2. Find the human_agree column robustly
    agree_col_name_actual <- grep("^human_agree", names(raw_data), value = TRUE)
    
    if (length(agree_col_name_actual) == 0) {
        stop("'human_agree'로 시작하는 컬럼을 찾을 수 없습니다.")
    }
    
    # 3. Select and rename robustly
    coder_data <- raw_data %>%
        select(
            unique_id,
            all_of(agree_col_name_actual)
        ) %>%
        rename(
            post_id = unique_id,
            human_agree_value = all_of(agree_col_name_actual)
        ) %>% 
        rename_with(~ paste0(coder_name, "_", .), -post_id)
    # --- END of new robust logic ---

    coder_data_list[[coder_name]] <- coder_data
    log_message("INFO", sprintf("%s 데이터 수집 완료", coder_name))

  }, error = function(e) {
    error_msg <- sprintf("%s 데이터 수집 실패: %s", coder_name, e$message)
    cat(sprintf("  ❌ %s\n", error_msg))
    log_message("ERROR", error_msg)
    failed_coders <- c(failed_coders, coder_name)
  })
  
  # API 제한 방지를 위한 대기
  if (i < nrow(sheet_info)) {
    Sys.sleep(2)
  }
}

# 수집 결과 요약
successful_coders <- length(coder_data_list)
failed_coders_count <- length(failed_coders)

cat(sprintf("\n📋 데이터 수집 결과: %d명 성공, %d명 실패\n", 
            successful_coders, failed_coders_count))

if (failed_coders_count > 0) {
  cat(sprintf("❌ 접근 실패한 코더: %s\n", paste(failed_coders, collapse = ", ")))
  cat("   (구글 시트 접근 권한 또는 URL 문제 가능성)\n")
}

# 작업 완료 상태 체크
incomplete_coders <- c()
for (coder_name in names(coder_data_list)) {
  agree_col <- paste0(coder_name, "_human_agree")
  if (agree_col %in% names(coder_data_list[[coder_name]])) {
    valid_responses <- sum(!is.na(coder_data_list[[coder_name]][[agree_col]]))
    if (valid_responses == 0) {
      incomplete_coders <- c(incomplete_coders, coder_name)
    }
  }
}

if (length(incomplete_coders) > 0) {
  cat(sprintf("⏳ 작업 미완료 코더: %s\n", paste(incomplete_coders, collapse = ", ")))
  cat("   (체크박스를 설정하지 않았거나 응답하지 않음)\n")
}

if (length(coder_data_list) < 2) {
  stop("❌ 최소 2명의 코더 데이터가 필요합니다.")
}

# 실제 응답한 코더 수 확인
responding_coders <- 0
for (coder_name in names(coder_data_list)) {
  agree_col <- paste0(coder_name, "_human_agree")
  if (agree_col %in% names(coder_data_list[[coder_name]])) {
    valid_responses <- sum(!is.na(coder_data_list[[coder_name]][[agree_col]]))
    if (valid_responses > 0) {
      responding_coders <- responding_coders + 1
    }
  }
}

if (responding_coders < 2) {
  cat("\n⚠️  경고: 실제 응답한 코더가 2명 미만입니다.\n")
  cat("신뢰도 분석 결과의 해석에 주의가 필요합니다.\n")
  cat("모든 코더가 작업을 완료한 후 다시 분석하는 것을 권장합니다.\n\n")
  
  user_continue <- readline("그래도 계속 진행하시겠습니까? (y/N): ")
  if (!tolower(user_continue) %in% c("y", "yes", "ㅇ")) {
    stop("분석을 중단합니다. 모든 코더의 작업 완료 후 다시 실행하세요.")
  }
} else {
  cat(sprintf("\n✅ %d명의 코더가 응답하여 신뢰도 분석을 진행합니다.\n", responding_coders))
}

# 데이터 병합 전 검증
cat("\n🔀 코더 데이터를 병합합니다...\n")
log_message("INFO", "코더 데이터 병합 시작")

# 병합 전 각 코더 데이터의 post_id 중복 확인 및 구조 분석
cat("🔍 병합 전 데이터 검증 중...\n")
for (coder_name in names(coder_data_list)) {
  data <- coder_data_list[[coder_name]]
  unique_ids <- length(unique(data$post_id))
  total_rows <- nrow(data)
  
  cat(sprintf("  %s: %d행, 고유 post_id: %d개", coder_name, total_rows, unique_ids))
  
  # 게시글/댓글 구성 분석
  post_only_count <- sum(!grepl("_", data$post_id))  # "_"가 없는 것 = 게시글만
  post_comment_count <- sum(grepl("_", data$post_id))  # "_"가 있는 것 = 게시글+댓글
  
  cat(sprintf(" (게시글: %d, 댓글: %d)", post_only_count, post_comment_count))
  
  if (total_rows != unique_ids) {
    cat(sprintf(" ⚠️  중복 post_id 발견! (%d개 중복)\n", total_rows - unique_ids))
    
    # 중복된 post_id 확인
    duplicate_ids <- data %>%
      count(post_id) %>%
      filter(n > 1) %>%
      head(3) %>%
      pull(post_id)
    
    if (length(duplicate_ids) > 0) {
      cat("    중복 ID 예시:", paste(duplicate_ids, collapse = ", "), "\n")
    }
    
    # 중복 제거
    coder_data_list[[coder_name]] <- data %>%
      distinct(post_id, .keep_all = TRUE)
    cat(sprintf("    중복 제거 후: %d행\n", nrow(coder_data_list[[coder_name]])))
  } else {
    cat(" ✅\n")
  }
}

# 첫 번째 코더 데이터를 기준으로 시작
merged_data <- coder_data_list[[1]]
coder_names <- names(coder_data_list)

cat(sprintf("\n기준 데이터: %s (%d행, %d개 고유 post_id)\n", 
            coder_names[1], nrow(merged_data), length(unique(merged_data$post_id))))

# 나머지 코더 데이터들을 순차적으로 병합
if (length(coder_data_list) > 1) {
  for (i in 2:length(coder_data_list)) {
    coder_name <- coder_names[i]
    current_data <- coder_data_list[[i]]
    
    before_merge <- nrow(merged_data)
    cat(sprintf("병합 중: %s (%d행) + 기존 %d행\n", coder_name, nrow(current_data), before_merge))
    
    # post_id 기준으로 full_join
    merged_data <- merged_data %>%
      full_join(current_data, by = "post_id", suffix = c("", "_dup"))
    
    after_merge <- nrow(merged_data)
    cat(sprintf("  병합 후: %d행 (증가: %d)\n", after_merge, after_merge - before_merge))
    
    # 비정상적인 증가 감지
    if (after_merge > before_merge * 2) {
      cat("  ⚠️  비정상적인 데이터 증가 감지! post_id 매칭 문제일 수 있습니다.\n")
      
      # 공통 post_id 확인
      common_ids <- intersect(
        coder_data_list[[1]]$post_id,
        current_data$post_id
      )
      cat(sprintf("  공통 post_id: %d개\n", length(common_ids)))
    }
    
    # 중복 컬럼 제거 (같은 이름으로 끝나는 _dup 컬럼들)
    dup_cols <- grep("_dup$", names(merged_data), value = TRUE)
    if (length(dup_cols) > 0) {
      merged_data <- merged_data %>% select(-all_of(dup_cols))
      cat(sprintf("  중복 컬럼 %d개 제거\n", length(dup_cols)))
    }
  }
}

cat(sprintf("✅ 병합 완료: %d개 항목, %d개 컬럼\n", nrow(merged_data), ncol(merged_data)))

# 비정상적으로 많은 행이 생성된 경우 경고
if (nrow(merged_data) > 100000) {
  cat("⚠️  경고: 병합된 데이터가 비정상적으로 큽니다!\n")
  cat("post_id 형식이나 데이터 구조에 문제가 있을 수 있습니다.\n")
  cat("각 코더 시트의 post_id 컬럼을 확인해주세요.\n\n")
  
  # 상위 5개 post_id 샘플 출력
  sample_ids <- head(unique(merged_data$post_id), 5)
  cat("샘플 post_id:\n")
  for (id in sample_ids) {
    cat(sprintf("  %s\n", id))
  }
}

log_message("INFO", sprintf("병합 완료: %d개 항목", nrow(merged_data)))

# 병합된 데이터의 컬럼 구조 확인
agree_cols <- grep("_human_agree$", names(merged_data), value = TRUE)
cat(sprintf("📊 발견된 동의 컬럼: %s\n", paste(agree_cols, collapse = ", ")))

# Krippendorff's Alpha 계산을 위한 데이터 준비
prepare_alpha_data <- function(merged_data, column_pattern) {

  # 해당 패턴의 컬럼들만 추출
  cols <- grep(column_pattern, names(merged_data), value = TRUE)
  
  if (length(cols) == 0) {
    log_message("WARN", sprintf("패턴 '%s'에 해당하는 컬럼을 찾을 수 없습니다.", column_pattern))
    return(data.frame())
  }
  
  cat(sprintf("🔍 분석 대상 컬럼: %s\n", paste(cols, collapse = ", ")))
  
  alpha_data <- merged_data[, cols, drop = FALSE]
  
  # 체크박스 데이터 정규화 (다양한 형태를 논리형으로 변환)
  for (col in cols) {
    values <- alpha_data[[col]]
    
    if (is.character(values)) {
      # 문자열 형태의 TRUE/FALSE 처리
      values <- toupper(trimws(values))
      alpha_data[[col]] <- case_when(
        values %in% c("TRUE", "T", "1", "YES", "Y") ~ TRUE,
        values %in% c("FALSE", "F", "0", "NO", "N") ~ FALSE,
        TRUE ~ NA
      )
    } else if (is.numeric(values)) {
      # 숫자 형태의 1/0 처리
      alpha_data[[col]] <- case_when(
        values == 1 ~ TRUE,
        values == 0 ~ FALSE,
        TRUE ~ NA
      )
    }
    # is.logical()인 경우 그대로 유지
  }
  
  # 완전한 케이스 (모든 코더의 응답이 있는 행)만 사용
  complete_rows <- complete.cases(alpha_data)
  alpha_data_complete <- alpha_data[complete_rows, , drop = FALSE]
  
  cat(sprintf("📊 데이터 준비 결과:\n"))
  cat(sprintf("  - 전체 항목: %d개\n", nrow(alpha_data)))
  cat(sprintf("  - 완료된 항목: %d개\n", nrow(alpha_data_complete)))
  cat(sprintf("  - 분석 참여 코더: %d명\n", ncol(alpha_data_complete)))
  
  log_message("INFO", sprintf("%s 분석 대상: %d개 완료된 케이스", 
                             column_pattern, nrow(alpha_data_complete)))
  
  return(alpha_data_complete)
}

# Krippendorff's Alpha 계산 (irr 패키지 사용)
calculate_krippendorff_alpha <- function(data_matrix, level = "nominal") {
  
  if (nrow(data_matrix) == 0) {
    log_message("WARN", "분석할 데이터가 없습니다.")
    return(list(alpha = NA, interpretation = "데이터 부족"))
  }
  
  cat(sprintf("🔄 Krippendorff's Alpha 계산 중... (%d개 항목, %d명 코더)\n", 
              nrow(data_matrix), ncol(data_matrix)))
  
  tryCatch({
    # 계산 시작 시간 기록
    start_time <- Sys.time()
    
    # 데이터 전치 (irr 패키지 요구사항)
    cat("  📊 데이터 전치 중...\n")
    transposed_data <- t(data_matrix)
    
    # irr 패키지의 kripp.alpha 함수 사용
    cat("  🧮 Alpha 값 계산 중...\n")
    result <- suppressWarnings(kripp.alpha(transposed_data, method = level))
    alpha_value <- result$value
    
    # 계산 완료 시간
    elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat(sprintf("  ✅ 계산 완료 (%.2f초 소요)\n", elapsed_time))
    
    # 해석 추가
    cat("  📋 결과 해석 중...\n")
    interpretation <- case_when(
      alpha_value >= 0.8 ~ "매우 높은 신뢰도 (Excellent)",
      alpha_value >= 0.67 ~ "높은 신뢰도 (Good)", 
      alpha_value >= 0.5 ~ "중간 신뢰도 (Moderate)",
      alpha_value >= 0.3 ~ "낮은 신뢰도 (Low)",
      TRUE ~ "매우 낮은 신뢰도 (Poor)"
    )
    
    cat(sprintf("  🎯 Alpha = %.3f (%s)\n", alpha_value, interpretation))
    
    return(list(
      alpha = alpha_value,
      interpretation = interpretation,
      n_items = nrow(data_matrix),
      n_raters = ncol(data_matrix),
      calculation_time = elapsed_time
    ))
    
  }, error = function(e) {
    cat("  ❌ 계산 실패\n")
    log_message("ERROR", sprintf("Alpha 계산 실패: %s", e$message))
    return(list(alpha = NA, interpretation = "계산 실패", error = e$message))
  })
}

# 신뢰도 분석 실행
cat("
🔬 Krippendorff's Alpha 신뢰도 분석을 시작합니다...\n")
log_message("INFO", "신뢰도 분석 시작")

# 동의/비동의 신뢰도 계산
cat("
📋 AI 분석 동의/비동의 일치도 계산 중...\n")
agreement_data <- prepare_alpha_data(merged_data, "_human_agree_value")

if (nrow(agreement_data) == 0) {
  log_message("ERROR", "분석할 동의/비동의 데이터가 없습니다.")
  stop("❌ human_agree 컬럼이 없거나 완료된 응답이 없습니다. 코더들이 작업을 완료했는지 확인하세요.")
}

agreement_alpha <- calculate_krippendorff_alpha(agreement_data, "nominal")

# 결과 정리
reliability_results <- list(
  agreement = agreement_alpha,
  analysis_date = Sys.time(),
  total_coders = length(coder_data_list),
  coder_names = names(coder_data_list)
)

# 결과 출력
cat("
")
cat(paste(rep("=", 65), collapse = ""), "\n")
cat("                 인간 코더 신뢰도 분석 결과\n")
cat(paste(rep("=", 65), collapse = ""), "\n")

cat(sprintf("📅 분석 일시: %s\n", format(reliability_results$analysis_date, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("👥 참여 코더: %d명 (%s)\n", 
            reliability_results$total_coders,
            paste(reliability_results$coder_names, collapse = ", ")))

cat("
🎯 신뢰도 분석 결과:\n")
alpha_value <- reliability_results$agreement$alpha %||% 0
interpretation <- reliability_results$agreement$interpretation %||% "분석 실패"

if (!is.na(alpha_value) && is.numeric(alpha_value)) {
  cat(sprintf("📊 AI 분석 동의/비동의 일치도: α = %.3f (%s)\n", alpha_value, interpretation))
  
  # 결과에 따른 색상 표시 (콘솔에서 구분)
  if (alpha_value >= 0.8) {
    cat("✅ 매우 높은 신뢰도 - AI 분석 결과를 신뢰할 수 있습니다!\n")
  } else if (alpha_value >= 0.67) {
    cat("🟡 높은 신뢰도 - AI 분석 결과를 사용할 수 있습니다.\n")
  } else if (alpha_value >= 0.5) {
    cat("🟠 중간 신뢰도 - 결과 해석 시 주의가 필요합니다.\n")
  } else {
    cat("🔴 낮은 신뢰도 - 추가 개선이 필요합니다.\n")
  }
} else {
  cat("❌ 신뢰도 계산에 실패했습니다.\n")
}

# 해석 가이드
cat("
📚 Krippendorff's Alpha 해석 가이드:\n")
cat("  • α ≥ 0.800: 매우 높은 신뢰도 (Excellent) - 결과 신뢰 가능\n")
cat("  • α ≥ 0.667: 높은 신뢰도 (Good) - 결과 사용 가능\n") 
cat("  • α ≥ 0.500: 중간 신뢰도 (Moderate) - 주의해서 해석\n")
cat("  • α < 0.500: 낮은 신뢰도 (Poor) - 추가 훈련 또는 재분석 필요\n")

# 결과 파일 저장
cat("
💾 결과 파일 저장 중...\n")
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
sample_label <- gsub("human_coding_info_|\\.csv", "", basename(selected_info_file))

# 상세 결과 저장
cat("  📊 상세 결과 저장 중... (RDS 형식)\n")
reliability_file <- file.path("results", sprintf("reliability_analysis_%s_%s.RDS", sample_label, timestamp))
saveRDS(reliability_results, reliability_file)
cat(sprintf("    저장 완료: %s\n", basename(reliability_file)))

# CSV 요약 저장 (정확도 정보 포함)
summary_df <- data.frame(
  metric = "AI_agreement",
  krippendorff_alpha = reliability_results$agreement$alpha %||% NA,
  interpretation = reliability_results$agreement$interpretation,
  n_cases = reliability_results$agreement$n_items %||% 0,
  n_coders = reliability_results$agreement$n_raters %||% 0,
  overall_accuracy_pct = reliability_results$overall_accuracy %||% NA,
  correct_items = if (!is.null(reliability_results$accuracy_summary)) {
    sum(reliability_results$accuracy_summary$n[reliability_results$accuracy_summary$ai_accuracy == "정답"], na.rm = TRUE)
  } else NA,
  ambiguous_items = if (!is.null(reliability_results$accuracy_summary)) {
    sum(reliability_results$accuracy_summary$n[reliability_results$accuracy_summary$ai_accuracy == "모호함"], na.rm = TRUE)
  } else NA,
  incorrect_items = if (!is.null(reliability_results$accuracy_summary)) {
    sum(reliability_results$accuracy_summary$n[reliability_results$accuracy_summary$ai_accuracy == "오답"], na.rm = TRUE)
  } else NA,
  analysis_date = format(reliability_results$analysis_date, "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)

cat("  📈 요약 결과 저장 중... (CSV 형식)\n")
summary_file <- file.path("results", sprintf("reliability_summary_%s_%s.csv", sample_label, timestamp))
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("    저장 완료: %s\n", basename(summary_file)))

# 병합된 원시 데이터도 저장 (추가 분석용)
cat("  📄 원시 데이터 저장 중... (CSV 형식)\n")
raw_data_file <- file.path("results", sprintf("merged_coder_data_%s_%s.csv", sample_label, timestamp))
write.csv(merged_data, raw_data_file, row.names = FALSE)
cat(sprintf("    저장 완료: %s\n", basename(raw_data_file)))

cat("💾 결과 파일이 성공적으로 저장되었습니다:\n")
cat(sprintf("  📊 상세 결과: %s\n", basename(reliability_file)))
cat(sprintf("  📈 요약 결과: %s\n", basename(summary_file)))
cat(sprintf("  📄 원시 데이터: %s\n", basename(raw_data_file)))

cat("
✨ 신뢰도 분석이 완료되었습니다!\n")
cat("🔍 요약 CSV 파일을 열어서 결과를 확인하거나,\n")
cat("📊 상세 RDS 파일을 R에서 불러와서 추가 분석을 수행할 수 있습니다.\n")

log_message("INFO", "=== 인간 코더 신뢰도 분석 완료 ===")

# AI 분석 정확도 평가
cat("
🎯 AI 분석 정확도 평가:\n")
cat("판정 기준: 3명 이상 동의=정답, 2명=모호함, 1명 이하=오답\n\n")

if (nrow(merged_data) > 0) {
  agreement_cols <- grep("_human_agree_value", names(merged_data), value = TRUE)
  
  if (length(agreement_cols) > 0) {
    cat(sprintf("🔄 정확도 판정 시작... (%d개 항목, %d명 코더)\n", 
                nrow(merged_data), length(agreement_cols)))
    
    # 각 항목별 동의 수 계산
    merged_data_with_judgment <- merged_data
    
    # 체크박스 값들을 논리형으로 정규화
    cat("  📊 체크박스 데이터 정규화 중...\n")
    for (i in seq_along(agreement_cols)) {
      col <- agreement_cols[i]
      cat(sprintf("    처리 중: %s (%d/%d)\n", 
                  gsub("_human_agree_value", "", col), i, length(agreement_cols)))
      
      values <- merged_data[[col]]
      if (is.character(values)) {
        values <- toupper(trimws(values))
        merged_data_with_judgment[[col]] <- case_when(
          values %in% c("TRUE", "T", "1", "YES", "Y") ~ TRUE,
          values %in% c("FALSE", "F", "0", "NO", "N") ~ FALSE,
          TRUE ~ NA
        )
      } else if (is.numeric(values)) {
        merged_data_with_judgment[[col]] <- case_when(
          values == 1 ~ TRUE,
          values == 0 ~ FALSE,
          TRUE ~ NA
        )
      }
    }
    
    # 각 항목별 동의 수 계산
    cat("  🧮 각 항목별 동의 수 계산 중...\n")
    merged_data_with_judgment$agreement_count <- rowSums(
      merged_data_with_judgment[, agreement_cols, drop = FALSE] == TRUE, 
      na.rm = TRUE
    )
    
    # 응답한 코더 수 계산
    cat("  📊 응답한 코더 수 계산 중...\n")
    merged_data_with_judgment$response_count <- rowSums(
      !is.na(merged_data_with_judgment[, agreement_cols, drop = FALSE])
    )
    
    # AI 분석 정확도 판정
    cat("  🎯 정확도 판정 적용 중...\n")
    merged_data_with_judgment$ai_accuracy <- case_when(
      merged_data_with_judgment$agreement_count >= 3 ~ "정답",
      merged_data_with_judgment$agreement_count == 2 ~ "모호함",
      merged_data_with_judgment$agreement_count <= 1 ~ "오답",
      TRUE ~ "판정불가"
    )
    
    # 정확도 통계 계산
    cat("  📈 통계 요약 계산 중...\n")
    accuracy_summary <- merged_data_with_judgment %>%
      filter(response_count > 0) %>%
      count(ai_accuracy) %>%
      mutate(percentage = round(n / sum(n) * 100, 1))
    
    cat("  ✅ 정확도 판정 완료!\n\n")
    
    cat("📊 AI 분석 정확도 결과:\n")
    for (i in 1:nrow(accuracy_summary)) {
      result <- accuracy_summary$ai_accuracy[i]
      count <- accuracy_summary$n[i]
      pct <- accuracy_summary$percentage[i]
      
      if (result == "정답") {
        cat(sprintf("  ✅ 정답: %d개 (%.1f%%)\n", count, pct))
      } else if (result == "모호함") {
        cat(sprintf("  🟡 모호함: %d개 (%.1f%%)\n", count, pct))
      } else if (result == "오답") {
        cat(sprintf("  ❌ 오답: %d개 (%.1f%%)\n", count, pct))
      } else {
        cat(sprintf("  ❓ %s: %d개 (%.1f%%)\n", result, count, pct))
      }
    }
    
    # 전체 정확도 (정답 비율)
    correct_items <- sum(accuracy_summary$n[accuracy_summary$ai_accuracy == "정답"], na.rm = TRUE)
    total_items <- sum(accuracy_summary$n)
    overall_accuracy <- if (total_items > 0) round(correct_items / total_items * 100, 1) else 0
    
    cat(sprintf("\n🎯 전체 AI 정확도: %.1f%% (%d/%d)\n", overall_accuracy, correct_items, total_items))
    
    # 코더별 동의율 요약
    cat("\n👥 코더별 동의율:\n")
    for (col in agreement_cols) {
      coder_name <- gsub("_human_agree_value", "", col)
      agree_count <- sum(merged_data_with_judgment[[col]] == TRUE, na.rm = TRUE)
      total_responses <- sum(!is.na(merged_data_with_judgment[[col]]))
      agree_rate <- if (total_responses > 0) round(agree_count / total_responses * 100, 1) else 0
      
      cat(sprintf("  • %s: %.1f%% (%d/%d)\n", coder_name, agree_rate, agree_count, total_responses))
    }
    
    # 상세 결과에 정확도 판정 추가
    reliability_results$accuracy_summary <- accuracy_summary
    reliability_results$overall_accuracy <- overall_accuracy
    reliability_results$detailed_judgments <- merged_data_with_judgment
    
  } else {
    cat("❌ 동의 컬럼을 찾을 수 없습니다.\n")
  }
} else {
  cat("❌ 분석할 데이터가 없습니다.\n")
}

# 개선 제안 및 경고
alpha_val <- reliability_results$agreement$alpha %||% 0
if (!is.na(alpha_val) && is.numeric(alpha_val)) {
  if (alpha_val < 0.67) {
    cat("\n⚠️  개선 권장사항 (신뢰도 < 0.67):\n")
    cat("  1. 📚 코더 교육 강화 및 평가 기준 재정립\n")
    cat("  2. 🧹 애매한 케이스 제거 후 재분석\n") 
    cat("  3. 🤖 AI 모델 또는 프롬프트 개선\n")
    cat("  4. 📋 평가 지침서 보완 및 예시 추가\n")
  } else if (alpha_val >= 0.8) {
    cat("\n🎉 우수한 신뢰도를 달성했습니다!\n")
    cat("  - AI 분석 결과를 연구에 활용할 수 있습니다.\n")
    cat("  - 현재 평가 기준과 프롬프트를 유지하세요.\n")
  }
}

# =============================================================================
# 추가 신뢰도 분석 (가중 합의 지수, 단순 일치율, 순서형 Alpha)
# =============================================================================

cat("\n")
cat(paste(rep("=", 65), collapse = ""), "\n")
cat("             추가 신뢰도 측정 분석\n")
cat(paste(rep("=", 65), collapse = ""), "\n")

# 가중 합의 지수 계산
cat("\n🔬 가중 합의 지수 분석 중...\n")
if (exists("merged_data") && nrow(merged_data) > 0) {
  weighted_result <- calculate_weighted_agreement_index(merged_data)
  
  if (!is.null(weighted_result$weighted_index) && !is.na(weighted_result$weighted_index)) {
    cat(sprintf("📊 가중 합의 지수: %.3f (%.1f%%)\n", 
                weighted_result$weighted_index, 
                weighted_result$weighted_index * 100))
    
    # 패턴 분석 결과 출력
    if (!is.null(weighted_result$pattern_summary)) {
      cat("📋 일치 패턴 분포:\n")
      for (pattern in names(weighted_result$pattern_summary)) {
        count <- weighted_result$pattern_summary[pattern]
        percentage <- round(count / weighted_result$n_items * 100, 1)
        cat(sprintf("  • %s: %d개 (%.1f%%)\n", pattern, count, percentage))
      }
    }
    
    # 신뢰도 결과에 추가
    reliability_results$weighted_agreement <- weighted_result
  } else {
    cat("❌ 가중 합의 지수 계산 실패\n")
  }
}

# 단순 일치율 계산
cat("\n🔬 단순 일치율 분석 중...\n")
if (exists("merged_data") && nrow(merged_data) > 0) {
  simple_result <- calculate_simple_agreement(merged_data)
  
  if (!is.null(simple_result$agreement_rate) && !is.na(simple_result$agreement_rate)) {
    cat(sprintf("📊 단순 일치율: %.3f (%.1f%%)\n", 
                simple_result$agreement_rate, 
                simple_result$agreement_rate * 100))
    
    # 코더별 TRUE 비율 출력
    if (!is.null(simple_result$coder_true_rates)) {
      cat("👥 코더별 TRUE 응답 비율:\n")
      for (coder_name in names(simple_result$coder_true_rates)) {
        rate <- simple_result$coder_true_rates[coder_name]
        cat(sprintf("  • %s: %.1f%%\n", 
                    gsub("_human_agree_value", "", coder_name), 
                    rate * 100))
      }
    }
    
    # 신뢰도 결과에 추가
    reliability_results$simple_agreement <- simple_result
  } else {
    cat("❌ 단순 일치율 계산 실패\n")
  }
}

# 순서형 Krippendorff's Alpha 계산
cat("\n🔬 순서형 Krippendorff's Alpha 분석 중...\n")
if (exists("merged_data") && nrow(merged_data) > 0) {
  ordinal_result <- calculate_ordinal_krippendorff_alpha(merged_data)
  
  if (!is.null(ordinal_result$alpha) && !is.na(ordinal_result$alpha)) {
    cat(sprintf("📊 순서형 Alpha: %.3f (%s)\n", 
                ordinal_result$alpha, 
                ordinal_result$interpretation))
    cat(sprintf("🔄 변환 방법: %s\n", ordinal_result$transformation))
    
    # 신뢰도 결과에 추가
    reliability_results$ordinal_alpha <- ordinal_result
  } else {
    cat("❌ 순서형 Alpha 계산 실패\n")
  }
}

# 종합 신뢰도 요약
cat("\n")
cat(paste(rep("=", 65), collapse = ""), "\n")
cat("               종합 신뢰도 분석 요약\n")
cat(paste(rep("=", 65), collapse = ""), "\n")

nominal_alpha <- reliability_results$agreement$alpha %||% NA
weighted_index <- reliability_results$weighted_agreement$weighted_index %||% NA
simple_rate <- reliability_results$simple_agreement$agreement_rate %||% NA
ordinal_alpha <- reliability_results$ordinal_alpha$alpha %||% NA

cat("📊 모든 신뢰도 측정값 요약:\n")
cat(sprintf("  • 명목형 Krippendorff's Alpha: %.3f\n", nominal_alpha %||% -999))
cat(sprintf("  • 순서형 Krippendorff's Alpha: %.3f\n", ordinal_alpha %||% -999))
cat(sprintf("  • 가중 합의 지수: %.3f (%.1f%%)\n", weighted_index %||% -999, (weighted_index %||% 0) * 100))
cat(sprintf("  • 단순 일치율: %.3f (%.1f%%)\n", simple_rate %||% -999, (simple_rate %||% 0) * 100))

# 권장사항
cat("\n💡 신뢰도 측정값 해석 가이드:\n")
cat("  • Krippendorff's Alpha: 우연 보정된 신뢰도 (전통적 지표)\n")
cat("  • 가중 합의 지수: 부분 일치 인정한 실용적 지표\n")
cat("  • 단순 일치율: 가장 직관적이고 이해하기 쉬운 지표\n")
cat("  • 순서형 Alpha: FALSE < TRUE 순서 관계를 고려한 지표\n")

cat(paste(rep("=", 65), collapse = ""), "\n")
cat("📁 파일 저장 및 완료 안내\n")
cat(paste(rep("=", 65), collapse = ""), "\n")

# Krippendorff's Alpha 계산 (irr 패키지 사용)
calculate_krippendorff_alpha <- function(data_matrix, level = "nominal") {
  
  if (nrow(data_matrix) == 0) {
    log_message("WARN", "분석할 데이터가 없습니다.")
    return(list(alpha = NA, interpretation = "데이터 부족"))
  }
  
  cat(sprintf("🔄 Krippendorff's Alpha 계산 중... (%d개 항목, %d명 코더)\n", 
              nrow(data_matrix), ncol(data_matrix)))
  
  tryCatch({
    # 계산 시작 시간 기록
    start_time <- Sys.time()
    
    # 데이터 전치 (irr 패키지 요구사항)
    cat("  📊 데이터 전치 중...\n")
    transposed_data <- t(data_matrix)
    
    # irr 패키지의 kripp.alpha 함수 사용
    cat("  🧮 Alpha 값 계산 중...\n")
    result <- suppressWarnings(kripp.alpha(transposed_data, method = level))
    alpha_value <- result$value
    
    # 계산 완료 시간
    elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat(sprintf("  ✅ 계산 완료 (%.2f초 소요)\n", elapsed_time))
    
    # 해석 추가
    cat("  📋 결과 해석 중...\n")
    interpretation <- case_when(
      alpha_value >= 0.8 ~ "매우 높은 신뢰도 (Excellent)",
      alpha_value >= 0.67 ~ "높은 신뢰도 (Good)", 
      alpha_value >= 0.5 ~ "중간 신뢰도 (Moderate)",
      alpha_value >= 0.3 ~ "낮은 신뢰도 (Low)",
      TRUE ~ "매우 낮은 신뢰도 (Poor)"
    )
    
    cat(sprintf("  🎯 Alpha = %.3f (%s)\n", alpha_value, interpretation))
    
    return(list(
      alpha = alpha_value,
      interpretation = interpretation,
      n_items = nrow(data_matrix),
      n_raters = ncol(data_matrix),
      calculation_time = elapsed_time
    ))
    
  }, error = function(e) {
    cat("  ❌ 계산 실패\n")
    log_message("ERROR", sprintf("Alpha 계산 실패: %s", e$message))
    return(list(alpha = NA, interpretation = "계산 실패", error = e$message))
  })
}
