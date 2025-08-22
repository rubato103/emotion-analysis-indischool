# 강제 체크박스 생성 스크립트
# 기존 시트에 체크박스를 확실히 생성하는 독립 스크립트

# 설정 및 유틸리티 로드
source("config.R")
source("utils.R")

# 필요한 패키지 로드
required_packages <- c("dplyr", "googlesheets4", "googledrive")
lapply(required_packages, library, character.only = TRUE)

# 시트 URL 입력받기
cat("=== 강제 체크박스 생성 도구 ===\n")
cat("체크박스를 생성할 구글 시트 URL을 입력하세요:\n")
sheet_url <- readline("URL: ")

if (sheet_url == "" || !grepl("docs.google.com/spreadsheets", sheet_url)) {
  stop("올바른 구글 시트 URL을 입력해주세요.")
}

# 시트 ID 추출
extract_sheet_id <- function(url) {
  pattern <- "spreadsheets/d/([a-zA-Z0-9_\\-]+)"
  match <- regexpr(pattern, url)
  if (match > 0) {
    full_match <- regmatches(url, match)
    return(gsub("spreadsheets/d/", "", full_match))
  }
  return(NULL)
}

sheet_id <- extract_sheet_id(sheet_url)
if (is.null(sheet_id)) {
  stop("시트 ID를 추출할 수 없습니다.")
}

cat(sprintf("추출된 시트 ID: %s\n", sheet_id))

# 구글 인증 확인
if (!gs4_has_token()) {
  cat("구글 시트 인증이 필요합니다.\n")
  gs4_auth(email = TRUE)
}

# 시트 정보 가져오기
tryCatch({
  sheet_info <- gs4_get(sheet_id)
  cat(sprintf("시트 이름: %s\n", sheet_info$name))
  
  # coding_data 시트에서 현재 데이터 읽기
  current_data <- range_read(sheet_id, sheet = "coding_data", col_names = TRUE)
  cat(sprintf("현재 데이터: %d행 × %d열\n", nrow(current_data), ncol(current_data)))
  
  # human_agree 컬럼 찾기
  if (!"human_agree" %in% names(current_data)) {
    stop("human_agree 컬럼을 찾을 수 없습니다.")
  }
  
  col_index <- which(names(current_data) == "human_agree")
  col_letter <- LETTERS[col_index]
  cat(sprintf("human_agree 컬럼 위치: %s열\n", col_letter))
  
}, error = function(e) {
  stop(sprintf("시트 정보를 가져올 수 없습니다: %s", e$message))
})

# 체크박스 강제 생성 함수
force_create_checkboxes <- function(sheet_id, col_letter, data_rows) {
  
  cat("\n=== 체크박스 강제 생성 시작 ===\n")
  
  # 1단계: 데이터 영역 정리
  start_row <- 2
  end_row <- data_rows + 1
  data_range <- sprintf("%s%d:%s%d", col_letter, start_row, col_letter, end_row)
  
  cat(sprintf("대상 범위: %s\n", data_range))
  
  # 2단계: 명시적 논리값으로 덮어쓰기
  tryCatch({
    cat("1. 논리값 데이터로 덮어쓰기...\n")
    
    # FALSE 논리값 벡터 생성
    logical_data <- rep(FALSE, data_rows)
    
    # 매트릭스 형태로 입력 (googlesheets4가 체크박스로 인식하도록)
    range_write(
      ss = sheet_id,
      data = matrix(logical_data, ncol = 1),
      sheet = "coding_data",
      range = data_range,
      col_names = FALSE,
      reformat = TRUE  # 자동 형식 적용
    )
    
    cat("✅ 논리값 데이터 입력 완료\n")
    Sys.sleep(2)
    
  }, error = function(e) {
    cat(sprintf("❌ 논리값 입력 실패: %s\n", e$message))
  })
  
  # 3단계: 헤더 업데이트
  tryCatch({
    cat("2. 헤더 업데이트...\n")
    
    header_range <- sprintf("%s1", col_letter)
    range_write(
      ss = sheet_id,
      data = matrix("human_agree (클릭=체크박스)", ncol = 1),
      sheet = "coding_data",
      range = header_range,
      col_names = FALSE
    )
    
    cat("✅ 헤더 업데이트 완료\n")
    
  }, error = function(e) {
    cat(sprintf("⚠️ 헤더 업데이트 실패: %s\n", e$message))
  })
  
  # 4단계: 수동 설정 안내 추가
  tryCatch({
    cat("3. 수동 설정 안내 추가...\n")
    
    # 빈 컬럼에 안내 추가 (Z컬럼 사용)
    instruction_range <- "Z1:Z5"
    instructions <- matrix(c(
      "📋 체크박스 수동 설정 방법:",
      sprintf("1. %s열 전체 선택", col_letter),
      "2. 상단 메뉴 '삽입' 클릭",
      "3. '체크박스' 선택",
      "4. 기존 FALSE가 체크박스로 변환됨"
    ), ncol = 1)
    
    range_write(
      ss = sheet_id,
      data = instructions,
      sheet = "coding_data",
      range = instruction_range,
      col_names = FALSE
    )
    
    cat("✅ 수동 설정 안내 추가 완료\n")
    
  }, error = function(e) {
    cat(sprintf("⚠️ 안내 추가 실패: %s\n", e$message))
  })
}

# 체크박스 생성 실행
force_create_checkboxes(sheet_id, col_letter, nrow(current_data))

cat("\n=== 체크박스 생성 완료 ===\n")
cat("📋 결과 확인 방법:\n")
cat("1. 구글 시트를 새로고침하세요\n")
cat(sprintf("2. %s열의 셀들을 클릭해보세요\n", col_letter))
cat("3. 체크박스가 나타나지 않으면:\n")
cat(sprintf("   - %s열 전체 선택\n", col_letter))
cat("   - 삽입 → 체크박스 클릭\n")
cat("   - FALSE 값들이 체크박스로 변환됨\n")
cat("\n✅ 작업 완료!\n")