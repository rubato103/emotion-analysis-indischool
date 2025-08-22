# 인간 코딩 시스템
# 샘플링 분석 결과를 4명의 코더용 구글 시트로 업로드

# 인간 코딩용 구글 시트 생성 및 업로드
create_human_coding_sheets <- function(analysis_results, sample_label = "SAMPLE") {
  
  if (!HUMAN_CODING_CONFIG$enable_human_coding) {
    log_message("INFO", "인간 코딩이 비활성화되어 있습니다.")
    return(NULL)
  }
  
  # 4단계 모드별 인간 코딩 대상 확인
  if (HUMAN_CODING_CONFIG$upload_sample_only && !grepl("SAMPLE|ADAPTIVE|PILOT|SAMPLING|CODE_CHECK", sample_label)) {
    log_message("INFO", "전체 분석(FULL)은 기본적으로 인간 코딩 대상이 아닙니다.")
    return(NULL)
  }
  
  # 코드 점검은 인간 코딩 생략
  if (grepl("CODE_CHECK", sample_label)) {
    log_message("INFO", "코드 점검 모드는 인간 코딩을 생략합니다.")
    return(NULL)
  }
  
  # 최소 샘플 크기 확인
  if (nrow(analysis_results) < HUMAN_CODING_CONFIG$min_sample_size) {
    log_message("WARN", sprintf("샘플 크기(%d)가 최소 요구사항(%d)보다 작습니다.", 
                                nrow(analysis_results), HUMAN_CODING_CONFIG$min_sample_size))
    return(NULL)
  }
  
  log_message("INFO", "인간 코딩용 구글 시트 생성을 시작합니다...")
  
  # 인간 코딩용 데이터 준비 (체크박스용 컬럼 포함)
  coding_data <- prepare_coding_data_with_checkbox(analysis_results)
  
  # 구글 인증 확인 및 설정
  tryCatch({
    # 기존 인증 상태 확인
    if (!gs4_has_token()) {
      log_message("INFO", "구글 시트 인증이 필요합니다. 브라우저를 통한 인증을 진행합니다...")
      gs4_auth(email = TRUE)  # 이메일 선택 옵션 활성화
    } else {
      log_message("INFO", "기존 구글 시트 인증 토큰을 사용합니다.")
    }
    
    # 구글 드라이브 인증도 동시에 설정
    if (!drive_has_token()) {
      drive_auth(token = gs4_token())  # 같은 토큰 공유
    }
    
  }, error = function(e) {
    log_message("ERROR", sprintf("구글 인증 설정 실패: %s", e$message))
    log_message("INFO", "🔑 구글 인증 문제 해결 방법:")
    log_message("INFO", "   1. 기존 인증 제거: gs4_deauth()")
    log_message("INFO", "   2. 새로운 인증: gs4_auth(email = TRUE)")
    log_message("INFO", "   3. 브라우저에서 구글 계정 선택 후 권한 승인")
    log_message("INFO", "   4. 문제 지속 시 다른 구글 계정 사용 고려")
  })
  
  # 4개 코더용 시트 생성
  sheet_urls <- list()
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M")
  
  for (i in 1:HUMAN_CODING_CONFIG$num_coders) {
    coder_name <- HUMAN_CODING_CONFIG$coder_names[i]
    
    tryCatch({
      # 시트 이름 생성
      sheet_title <- sprintf("emotion_analysis_%s_%s_%s", 
                            sample_label, coder_name, timestamp)
      
      # 구글 시트 생성
      created_sheet <- gs4_create(
        name = sheet_title,
        sheets = list(coding_data = coding_data)
      )
      
      # 시트 서식 적용
      apply_sheet_formatting(created_sheet, coding_data)
      
      sheet_urls[[coder_name]] <- gs4_get(created_sheet)$spreadsheet_url
      
      log_message("INFO", sprintf("%s용 시트 생성 완료: %s", coder_name, sheet_title))
      
      # API 제한 방지를 위한 대기
      Sys.sleep(2)
      
    }, error = function(e) {
      error_msg <- e$message
      
      # 오류 유형별 상세 메시지 제공
      if (grepl("PERMISSION_DENIED", error_msg) || grepl("403", error_msg)) {
        log_message("ERROR", sprintf("%s 시트 생성 실패: 구글 시트 생성 권한 부족", coder_name))
        log_message("INFO", "💡 해결 방법:")
        log_message("INFO", "   1. 구글 계정 인증 상태 확인: gs4_auth(email = TRUE)")
        log_message("INFO", "   2. 구글 드라이브 저장소 공간 확인")
        log_message("INFO", "   3. 다른 구글 계정으로 인증 시도")
      } else if (grepl("RATE_LIMIT", error_msg) || grepl("429", error_msg)) {
        log_message("ERROR", sprintf("%s 시트 생성 실패: API 요청 제한 초과", coder_name))
        log_message("INFO", "💡 잠시 후 다시 시도하거나 대기 시간을 늘리세요.")
      } else if (grepl("QUOTA_EXCEEDED", error_msg)) {
        log_message("ERROR", sprintf("%s 시트 생성 실패: 구글 API 할당량 초과", coder_name))
        log_message("INFO", "💡 24시간 후 다시 시도하거나 다른 계정을 사용하세요.")
      } else {
        log_message("ERROR", sprintf("%s 시트 생성 실패: %s", coder_name, error_msg))
        log_message("INFO", "💡 네트워크 연결을 확인하고 다시 시도하세요.")
      }
    })
  }
  
  # 폴더로 이동
  if (length(sheet_urls) > 0) {
    move_sheets_to_folder(sheet_urls, sample_label, timestamp)
  }
  
  # 결과 처리 및 안내
  if (length(sheet_urls) == 0) {
    log_message("ERROR", "인간 코딩 시트 생성 실패: 모든 시트 생성이 실패했습니다.")
    log_message("INFO", "💡 대안 방법:")
    log_message("INFO", "   1. 로컬 CSV 파일로 내보내기: write.csv(analysis_results, 'human_coding.csv')")
    log_message("INFO", "   2. 구글 인증 재설정: gs4_deauth() 후 gs4_auth(email = TRUE)")
    log_message("INFO", "   3. 다른 구글 계정 사용 고려")
    
    # CSV 파일로 대안 제공
    create_local_coding_files(coding_data, sample_label, timestamp)
    
    return(NULL)
  } else if (length(sheet_urls) < HUMAN_CODING_CONFIG$num_coders) {
    log_message("WARN", sprintf("인간 코딩 시트 생성 부분 성공: %d/%d개 시트 생성", 
                               length(sheet_urls), HUMAN_CODING_CONFIG$num_coders))
  } else {
    log_message("INFO", sprintf("인간 코딩 시트 생성 완료: %d개 시트", length(sheet_urls)))
  }
  
  # 생성된 시트 정보 저장
  save_sheet_info(sheet_urls, sample_label, timestamp)
  
  return(sheet_urls)
}

# 인간 코딩용 데이터 준비
prepare_coding_data <- function(analysis_results) {
  
  coding_data <- analysis_results %>%
    # 필요한 컬럼만 선택하고 순서 지정
    select(
      post_id,                         # 아이디
      content,                         # 콘텐츠
      any_of(c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대")), # 플루치크 8대 기본감정
      dominant_emotion,                # 지배감정
      P, A, D,                        # PAD 점수
      complex_emotion,                # 복합감정
      emotion_scores_rationale,        # 감정 점수 근거
      PAD_analysis,                   # PAD 분석 근거
      complex_emotion_reasoning       # 복합감정 추론
    ) %>%
    # 인간 코딩용 컬럼 추가
    mutate(
      human_agree = NA_character_     # 동의/비동의 (체크박스)
    ) %>%
    # 최종 컬럼 순서 정렬
    select(
      post_id,                        # 아이디
      content,                        # 콘텐츠  
      기쁨, 신뢰, 공포, 놀람, 슬픔, 혐오, 분노, 기대, # 플루치크 8대 기본감정
      dominant_emotion,               # 지배감정
      P, A, D,                       # PAD 점수
      complex_emotion,               # 복합감정
      emotion_scores_rationale,      # 감정 점수 근거
      PAD_analysis,                  # PAD 분석 근거
      complex_emotion_reasoning,     # 복합감정 추론
      human_agree                    # 인간 동의 여부
    )
  
  return(coding_data)
}

# 체크박스 친화적인 데이터 준비 함수
prepare_coding_data_with_checkbox <- function(analysis_results) {
  
  # 디버깅: 사용 가능한 컬럼 확인
  log_message("INFO", sprintf("입력 데이터 크기: %d행 × %d열", nrow(analysis_results), ncol(analysis_results)))
  log_message("INFO", sprintf("사용 가능한 컬럼: %s", paste(names(analysis_results), collapse = ", ")))
  
  # 각 컬럼 그룹별로 존재하는 컬럼 확인
  id_cols <- intersect(names(analysis_results), c("post_id", "comment_id", "id", "unique_id"))
  content_cols <- intersect(names(analysis_results), c("content", "text", "내용"))
  emotion_cols <- intersect(names(analysis_results), c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대"))
  
  log_message("INFO", sprintf("ID 컬럼: %s", ifelse(length(id_cols) > 0, paste(id_cols, collapse = ", "), "없음")))
  log_message("INFO", sprintf("콘텐츠 컬럼: %s", ifelse(length(content_cols) > 0, paste(content_cols, collapse = ", "), "없음")))
  log_message("INFO", sprintf("감정 컬럼: %s", ifelse(length(emotion_cols) > 0, paste(emotion_cols, collapse = ", "), "없음")))
  
  # 최소한의 필수 컬럼이 있는지 확인
  if (length(content_cols) == 0) {
    stop("콘텐츠 컬럼을 찾을 수 없습니다. content, text, 내용 중 하나가 필요합니다.")
  }
  
  # ID 컬럼이 없으면 행 번호로 생성
  if (length(id_cols) == 0) {
    log_message("WARN", "ID 컬럼이 없어서 행 번호로 ID를 생성합니다.")
    analysis_results$row_id <- 1:nrow(analysis_results)
    id_cols <- "row_id"
  }
  
  coding_data <- analysis_results %>%
    # 존재하는 컬럼만 선택 (post_id와 comment_id 모두 포함)
    select(
      any_of(c("post_id")),                    # post_id (필수)
      any_of(c("comment_id")),                 # comment_id (있으면 포함)
      all_of(content_cols[1]),                 # 첫 번째 콘텐츠 컬럼
      any_of(c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대")), # 플루치크 8대 기본감정
      any_of(c("dominant_emotion", "지배감정")), # 지배감정
      any_of(c("P", "A", "D")),                # PAD 점수
      any_of(c("complex_emotion", "복합감정")), # 복합감정
      any_of(c("emotion_scores_rationale", "감정점수근거")), # 감정 점수 근거
      any_of(c("PAD_analysis", "PAD분석근거")), # PAD 분석 근거
      any_of(c("complex_emotion_reasoning", "복합감정추론")), # 복합감정 추론
      any_of(c("rationale", "근거", "분석근거"))    # 근거
    ) %>%
    # 체크박스용 컬럼 추가 (논리값으로 초기화)
    mutate(
      human_agree = as.logical(FALSE)  # 명시적으로 논리값 설정
    ) %>%
    # 실제로 존재하는 컬럼들을 우선순위에 따라 재정렬
    select(
      any_of(c("post_id")),                    # post_id
      any_of(c("comment_id")),                 # comment_id (있으면)
      all_of(content_cols[1]),                 # 확인된 콘텐츠 컬럼
      any_of(c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대")), # 플루치크 8대 기본감정
      any_of(c("dominant_emotion", "지배감정")),
      any_of(c("P", "A", "D")),
      any_of(c("complex_emotion", "복합감정")),
      any_of(c("emotion_scores_rationale", "감정점수근거")), # 감정 점수 근거
      any_of(c("PAD_analysis", "PAD분석근거")), # PAD 분석 근거
      any_of(c("complex_emotion_reasoning", "복합감정추론")), # 복합감정 추론
      human_agree
    )
  
  log_message("INFO", sprintf("최종 코딩 데이터: %d행 × %d열", nrow(coding_data), ncol(coding_data)))
  log_message("INFO", sprintf("최종 컬럼: %s", paste(names(coding_data), collapse = ", ")))
  
  return(coding_data)
}

# 시트 서식 적용 및 체크박스 생성
apply_sheet_formatting <- function(sheet, data) {
  
  tryCatch({
    # 데이터를 먼저 작성
    sheet_write(data, sheet, sheet = "coding_data")
    log_message("INFO", "시트 기본 데이터 작성 완료")
    
    # 체크박스 준비 (수동 설정 최적화)
    sheet_id <- extract_sheet_id(gs4_get(sheet)$spreadsheet_url)
    if (!is.null(sheet_id)) {
      prepare_for_manual_checkbox_setup(sheet_id, data)
    }
    
    # 참고 시트 추가 (수동 설정 중심 안내)
    reference_data <- data.frame(
      단계 = c(
        "🔧 체크박스 수동 설정 가이드",
        "",
        "⚠️ 중요 안내",
        "",
        "📋 체크박스 설정 방법",
        "   Step 1",
        "   Step 2", 
        "   Step 3",
        "   Step 4",
        "   Step 5",
        "",
        "💡 설정 완료 확인",
        "",
        "📱 모바일/태블릿 사용법",
        "",
        "📊 데이터 설명",
        "",
        "",
        "",
        "",
        ""
      ),
      설명 = c(
        "human_agree 열에 체크박스를 수동으로 설정하는 방법",
        "코딩 작업 전에 반드시 이 설정을 완료해주세요!",
        "현재 human_agree 열에는 FALSE 텍스트가 입력되어 있습니다",
        "이를 체크박스로 변환해야 합니다",
        "다음 단계를 정확히 따라하세요:",
        "human_agree 열 헤더(컬럼명)를 클릭하여 전체 열 선택",
        "상단 메뉴바에서 '삽입(Insert)' 메뉴 클릭",
        "드롭다운에서 '체크박스(Checkbox)' 옵션 선택",
        "기존 FALSE 텍스트가 모두 체크박스로 자동 변환됨",
        "각 셀을 클릭하여 TRUE(체크)/FALSE(해제) 전환 가능",
        "설정이 완료되면 코딩 작업을 시작하세요",
        "체크박스 설정 후 각 행의 human_agree 셀을 클릭해보세요",
        "클릭할 때마다 체크/해제가 전환되면 설정 성공입니다",
        "모바일: 셀을 길게 터치 → 서식 → 체크박스",
        "태블릿: 열 선택 → 도구 모음 → 체크박스",
        "기쁨~중립: AI가 분석한 8개 감정별 점수 (0.00~1.00)",
        "지배감정: AI가 판단한 주요 감정",
        "P(쾌락), A(각성), D(지배): PAD 모델 점수 (-1.00~1.00)",
        "복합감정: PAD 모델 기반 복합 감정 명칭",
        "분석근거: AI 분석의 논리적 근거",
        "human_agree: 동의(체크)/비동의(해제) - 체크박스 설정 필수"
      )
    )
    
    sheet_write(reference_data, sheet, sheet = "참고사항")
    
  }, error = function(e) {
    log_message("WARN", sprintf("시트 서식 적용 중 오류: %s", e$message))
  })
}

# Google Sheets API를 통한 체크박스 자동 추가 함수 (확실한 생성 버전)
add_checkboxes_to_sheet <- function(sheet_id, data) {
  
  tryCatch({
    log_message("INFO", "체크박스 자동 생성을 시작합니다...")
    
    # human_agree 컬럼 위치 찾기
    col_names <- names(data)
    checkbox_col_index <- which(col_names == "human_agree")
    
    if (length(checkbox_col_index) == 0) {
      log_message("WARN", "human_agree 컬럼을 찾을 수 없습니다.")
      return(FALSE)
    }
    
    # Google Sheets API 인증 확인 및 재설정
    if (!gs4_has_token()) {
      log_message("WARN", "Google Sheets 인증이 필요합니다.")
      tryCatch({
        gs4_auth(email = TRUE)  # 이메일 선택 옵션으로 재인증
        if (!gs4_has_token()) {
          stop("인증 토큰을 가져올 수 없습니다.")
        }
      }, error = function(e) {
        log_message("ERROR", sprintf("Google Sheets 재인증 실패: %s", e$message))
        return(FALSE)
      })
    }
    
    # 체크박스를 적용할 범위 계산
    start_row <- 2  # 헤더 다음 행부터
    end_row <- nrow(data) + 1  # 데이터 마지막 행까지
    checkbox_col_letter <- LETTERS[checkbox_col_index]  # 컬럼 인덱스를 문자로 변환
    
    log_message("INFO", sprintf("체크박스 적용 범위: %s%d:%s%d", 
                               checkbox_col_letter, start_row, 
                               checkbox_col_letter, end_row))
    
    # 방법 1: googlesheets4의 내장 기능으로 먼저 시도
    tryCatch({
      log_message("INFO", "방법 1: googlesheets4 내장 기능으로 체크박스 생성 시도...")
      
      # 범위 지정
      checkbox_range <- sprintf("%s%d:%s%d", checkbox_col_letter, start_row, checkbox_col_letter, end_row)
      
      # googlesheets4 안전한 방법: 데이터프레임으로 논리값 입력
      checkbox_df <- data.frame(human_agree = rep(as.logical(FALSE), nrow(data)))
      
      range_write(
        ss = sheet_id,
        data = checkbox_df,
        sheet = "coding_data",
        range = checkbox_range,
        col_names = FALSE,
        reformat = TRUE  # 서식 자동 적용 활성화
      )
      
      # 체크박스가 제대로 생성되었는지 확인하기 위해 잠시 대기
      Sys.sleep(1)
      
      log_message("INFO", "✅ 방법 1 성공: googlesheets4 내장 기능으로 체크박스 생성 완료")
      log_message("INFO", "🎯 코더는 이제 체크박스를 클릭하여 TRUE/FALSE로 동의/비동의를 표시할 수 있습니다!")
      return(TRUE)
      
    }, error = function(method1_error) {
      log_message("WARN", sprintf("방법 1 실패: %s", method1_error$message))
      
      # 방법 2: Google Sheets API batchUpdate 직접 호출
      tryCatch({
        log_message("INFO", "방법 2: Google Sheets API batchUpdate로 체크박스 생성 시도...")
        
        # batchUpdate 요청 구성
        requests <- list(
          list(
            repeatCell = list(
              range = list(
                sheetId = 0,  # 첫 번째 시트
                startRowIndex = start_row - 1,  # 0-based index
                endRowIndex = end_row,
                startColumnIndex = checkbox_col_index - 1,  # 0-based index
                endColumnIndex = checkbox_col_index
              ),
              cell = list(
                dataValidation = list(
                  condition = list(
                    type = "BOOLEAN"
                  ),
                  inputMessage = "동의하면 체크, 비동의하면 체크 해제",
                  showCustomUi = TRUE
                )
              ),
              fields = "dataValidation"
            )
          )
        )
        
        # API 호출 실행 (토큰 안전성 확인)
        request_body <- list(requests = requests)
        token <- gs4_token()
        
        # 토큰 구조 확인 및 액세스 토큰 추출
        access_token <- NULL
        if (!is.null(token$credentials$access_token)) {
          access_token <- token$credentials$access_token
        } else if (!is.null(token$token$access_token)) {
          access_token <- token$token$access_token
        } else {
          stop("Google Sheets 인증 토큰을 가져올 수 없습니다.")
        }
        
        response <- httr2::request(sprintf("https://sheets.googleapis.com/v4/spreadsheets/%s:batchUpdate", sheet_id)) %>%
          httr2::req_auth_bearer_token(access_token) %>%
          httr2::req_headers("Content-Type" = "application/json") %>%
          httr2::req_body_json(request_body) %>%
          httr2::req_perform()
        
        if (httr2::resp_status(response) == 200) {
          log_message("INFO", "✅ 방법 2 성공: API로 체크박스 데이터 검증 설정 완료")
          
          # 기본값을 FALSE로 설정
          checkbox_range <- sprintf("%s%d:%s%d", checkbox_col_letter, start_row, checkbox_col_letter, end_row)
          checkbox_data <- data.frame(human_agree = rep(FALSE, nrow(data)))
          
          range_write(
            ss = sheet_id,
            data = checkbox_data,
            sheet = "coding_data", 
            range = checkbox_range,
            col_names = FALSE,
            reformat = FALSE
          )
          
          log_message("INFO", "✅ 체크박스 기본값(FALSE) 설정 완료")
          log_message("INFO", "🎯 코더는 이제 체크박스를 클릭하여 TRUE/FALSE로 동의/비동의를 표시할 수 있습니다!")
          return(TRUE)
          
        } else {
          error_content <- httr2::resp_body_string(response)
          stop(sprintf("API 호출 실패: HTTP %d - %s", httr2::resp_status(response), error_content))
        }
        
      }, error = function(method2_error) {
        log_message("ERROR", sprintf("방법 2 실패: %s", method2_error$message))
        
        # 방법 3: 최종 대안 - FALSE 텍스트와 상세 안내
        log_message("INFO", "방법 3: 대안 방법으로 논리값 입력 및 수동 설정 안내...")
        
        tryCatch({
          checkbox_range <- sprintf("%s%d:%s%d", checkbox_col_letter, start_row, checkbox_col_letter, end_row)
          checkbox_data <- data.frame(human_agree = rep(FALSE, nrow(data)))
          
          range_write(
            ss = sheet_id,
            data = checkbox_data,
            sheet = "coding_data",
            range = checkbox_range,
            col_names = FALSE,
            reformat = FALSE
          )
          
          log_message("WARN", "⚠️ 자동 체크박스 생성에 실패했습니다.")
          log_message("INFO", "FALSE 값이 입력되었습니다. '참고사항' 시트에서 수동 설정 방법을 확인하세요.")
          log_message("INFO", sprintf("📍 수동 설정: %s 열을 선택 → 삽입 → 체크박스", checkbox_col_letter))
          return(FALSE)
          
        }, error = function(method3_error) {
          log_message("ERROR", sprintf("모든 방법 실패: %s", method3_error$message))
          return(FALSE)
        })
      })
    })
    
  }, error = function(e) {
    log_message("ERROR", sprintf("체크박스 자동 생성 중 치명적 오류: %s", e$message))
    log_message("INFO", "수동으로 체크박스를 설정해주세요. '참고사항' 시트를 참고하세요.")
    return(FALSE)
  })
}

# 시트를 폴더로 이동
move_sheets_to_folder <- function(sheet_urls, sample_label, timestamp) {
  
  tryCatch({
    folder_name <- sprintf("%s_%s_%s", 
                          HUMAN_CODING_CONFIG$gdrive_folder, 
                          sample_label, 
                          timestamp)
    
    # 폴더 검색 또는 생성
    folder_info <- drive_find(
      q = sprintf("name = '%s' and mimeType = 'application/vnd.google-apps.folder' and trashed = false", 
                  folder_name), 
      n_max = 1
    )
    
    if (nrow(folder_info) == 0) {
      folder_info <- drive_mkdir(name = folder_name)
      log_message("INFO", sprintf("'%s' 폴더를 새로 생성했습니다.", folder_name))
    }
    
    # 각 시트를 폴더로 이동
    for (coder_name in names(sheet_urls)) {
      url <- sheet_urls[[coder_name]]
      sheet_id <- extract_sheet_id(url)
      
      if (!is.null(sheet_id)) {
        drive_mv(file = as_id(sheet_id), path = folder_info)
        log_message("INFO", sprintf("%s 시트를 폴더로 이동했습니다.", coder_name))
      }
    }
    
  }, error = function(e) {
    log_message("WARN", sprintf("폴더 이동 중 오류: %s", e$message))
  })
}

# 구글 시트 URL에서 ID 추출
extract_sheet_id <- function(url) {
  if (is.null(url) || url == "") return(NULL)
  
  # URL 패턴에서 시트 ID 추출 (Windows 호환)
  pattern <- "spreadsheets/d/([a-zA-Z0-9_\\-]+)"
  match <- regexpr(pattern, url)
  
  if (match > 0) {
    full_match <- regmatches(url, match)
    sheet_id <- gsub("spreadsheets/d/", "", full_match)
    return(sheet_id)
  }
  
  return(NULL)
}

# 시트 정보 저장
save_sheet_info <- function(sheet_urls, sample_label, timestamp) {
  
  sheet_info <- data.frame(
    coder = names(sheet_urls),
    sheet_url = unlist(sheet_urls),
    sample_label = sample_label,
    created_date = Sys.time(),
    timestamp = timestamp,
    status = "created",
    stringsAsFactors = FALSE
  )
  
  info_file <- file.path("results", sprintf("human_coding_info_%s_%s.csv", sample_label, timestamp))
  write.csv(sheet_info, info_file, row.names = FALSE)
  
  log_message("INFO", sprintf("시트 정보를 %s에 저장했습니다.", info_file))
  
  # 콘솔에 URL 출력
  cat("\n=== 인간 코딩용 구글 시트 URL ===\n")
  for (i in 1:length(sheet_urls)) {
    coder_name <- names(sheet_urls)[i]
    url <- sheet_urls[[i]]
    cat(sprintf("%s: %s\n", coder_name, url))
  }
  cat("\n코더들에게 위 URL을 전달해주세요!\n")
  
  return(sheet_info)
}

# Null-coalescing operator는 utils.R에서 정의됨

# 강력한 체크박스 생성 헬퍼 함수
ensure_checkbox_creation <- function(sheet_id, data) {
  
  # human_agree 컬럼 위치 찾기
  col_names <- names(data)
  checkbox_col_index <- which(col_names == "human_agree")
  
  if (length(checkbox_col_index) == 0) {
    log_message("ERROR", "human_agree 컬럼을 찾을 수 없습니다.")
    return(FALSE)
  }
  
  # 체크박스 적용 범위
  start_row <- 2
  end_row <- nrow(data) + 1
  checkbox_col_letter <- LETTERS[checkbox_col_index]
  
  tryCatch({
    log_message("INFO", "확실한 체크박스 생성 방법 적용 중...")
    
    # 1단계: 데이터 검증 설정 (BOOLEAN 타입 강제)
    validation_requests <- list(
      list(
        repeatCell = list(
          range = list(
            sheetId = 0,
            startRowIndex = start_row - 1,
            endRowIndex = end_row,
            startColumnIndex = checkbox_col_index - 1,
            endColumnIndex = checkbox_col_index
          ),
          cell = list(
            dataValidation = list(
              condition = list(type = "BOOLEAN"),
              inputMessage = "동의=체크(TRUE), 비동의=해제(FALSE)",
              showCustomUi = TRUE,
              strict = TRUE
            )
          ),
          fields = "dataValidation"
        )
      )
    )
    
    # 2단계: 셀 서식 설정 (체크박스 스타일)
    format_requests <- list(
      list(
        repeatCell = list(
          range = list(
            sheetId = 0,
            startRowIndex = start_row - 1,
            endRowIndex = end_row,
            startColumnIndex = checkbox_col_index - 1,
            endColumnIndex = checkbox_col_index
          ),
          cell = list(
            userEnteredFormat = list(
              horizontalAlignment = "CENTER",
              backgroundColorStyle = list(
                rgbColor = list(red = 0.95, green = 0.98, blue = 0.95)
              )
            )
          ),
          fields = "userEnteredFormat"
        )
      )
    )
    
    # API 호출 준비 및 토큰 확인 (디버깅 강화)
    tryCatch({
      # 인증 상태 재확인
      if (!gs4_has_token()) {
        log_message("WARN", "인증 토큰이 없습니다. 재인증을 시도합니다...")
        gs4_auth(email = TRUE)
      }
      
      token <- gs4_token()
      if (is.null(token)) {
        stop("인증 토큰을 가져올 수 없습니다.")
      }
      
      # 토큰 구조 디버깅
      log_message("INFO", sprintf("토큰 클래스: %s", paste(class(token), collapse = ", ")))
      
      # googlesheets4 버전별 토큰 처리
      access_token <- NULL
      
      # 새로운 방법: gargle 패키지의 token_fetch() 사용
      tryCatch({
        # gargle을 통한 토큰 가져오기
        actual_token <- gargle::token_fetch()
        if (!is.null(actual_token) && !is.null(actual_token$credentials$access_token)) {
          access_token <- actual_token$credentials$access_token
          log_message("INFO", "gargle token_fetch()로 액세스 토큰 추출 성공")
        }
      }, error = function(e) {
        log_message("WARN", sprintf("gargle token_fetch() 실패: %s", e$message))
      })
      
      # 기존 방법들도 시도
      if (is.null(access_token)) {
        # 방법 1: httr2 토큰 구조
        if (inherits(token, "httr2_token") && !is.null(token$access_token)) {
          access_token <- token$access_token
          log_message("INFO", "httr2 토큰에서 액세스 토큰 추출 성공")
        }
        # 방법 2: 기존 방식
        else if (!is.null(token$credentials) && !is.null(token$credentials$access_token)) {
          access_token <- token$credentials$access_token
          log_message("INFO", "credentials에서 액세스 토큰 추출 성공")
        }
        # 방법 3: token 구조
        else if (!is.null(token$token) && !is.null(token$token$access_token)) {
          access_token <- token$token$access_token
          log_message("INFO", "token에서 액세스 토큰 추출 성공")
        }
      }
      
      if (is.null(access_token) || access_token == "") {
        log_message("WARN", "모든 방법으로 액세스 토큰 추출 실패 - API 방법 건너뛰기")
        # API 없이 작동하는 방법으로 즉시 폴백
        stop("API 토큰 추출 실패")
      }
      
      log_message("INFO", "Google Sheets API 토큰 확인 완료")
      
    }, error = function(e) {
      log_message("ERROR", sprintf("토큰 준비 실패: %s", e$message))
      # 토큰 없이도 작동할 수 있는 방법으로 폴백
      return(FALSE)
    })
    
    # 1단계 실행: 데이터 검증 설정
    validation_body <- list(requests = validation_requests)
    validation_response <- httr2::request(sprintf("https://sheets.googleapis.com/v4/spreadsheets/%s:batchUpdate", sheet_id)) %>%
      httr2::req_auth_bearer_token(access_token) %>%
      httr2::req_headers("Content-Type" = "application/json") %>%
      httr2::req_body_json(validation_body) %>%
      httr2::req_perform()
    
    if (httr2::resp_status(validation_response) != 200) {
      stop(sprintf("데이터 검증 설정 실패: HTTP %d", httr2::resp_status(validation_response)))
    }
    
    log_message("INFO", "✅ BOOLEAN 데이터 검증 설정 완료")
    Sys.sleep(1)
    
    # 2단계 실행: 서식 설정
    format_body <- list(requests = format_requests)
    format_response <- httr2::request(sprintf("https://sheets.googleapis.com/v4/spreadsheets/%s:batchUpdate", sheet_id)) %>%
      httr2::req_auth_bearer_token(access_token) %>%
      httr2::req_headers("Content-Type" = "application/json") %>%
      httr2::req_body_json(format_body) %>%
      httr2::req_perform()
    
    if (httr2::resp_status(format_response) != 200) {
      log_message("WARN", "서식 설정은 실패했지만 체크박스 기능은 정상 작동할 것입니다.")
    } else {
      log_message("INFO", "✅ 체크박스 서식 설정 완료")
    }
    
    Sys.sleep(1)
    
    # 3단계: 논리값 데이터 입력 (체크박스로 자동 변환)
    checkbox_range <- sprintf("%s%d:%s%d", checkbox_col_letter, start_row, checkbox_col_letter, end_row)
    logical_values <- rep(as.logical(FALSE), nrow(data))
    
    # 명시적으로 논리값 매트릭스로 입력
    range_write(
      ss = sheet_id,
      data = matrix(logical_values, ncol = 1),
      sheet = "coding_data",
      range = checkbox_range,
      col_names = FALSE,
      reformat = FALSE
    )
    
    log_message("INFO", "✅ 논리값 데이터 입력 완료")
    Sys.sleep(2)  # 구글 시트가 체크박스로 변환할 시간 확보
    
    log_message("INFO", "🎯 체크박스 생성이 완료되었습니다!")
    log_message("INFO", "📋 코더 안내: 셀을 클릭하면 체크박스가 나타나며, 클릭으로 TRUE/FALSE 전환 가능")
    
    return(TRUE)
    
  }, error = function(e) {
    log_message("ERROR", sprintf("확실한 체크박스 생성 실패: %s", e$message))
    return(FALSE)
  })
}

# 단순하고 안전한 체크박스 생성 방법 (토큰 문제 해결용)
create_simple_checkbox <- function(sheet_id, data) {
  
  tryCatch({
    log_message("INFO", "단순한 체크박스 생성 방법을 시도합니다...")
    
    # human_agree 컬럼 위치 찾기
    col_names <- names(data)
    checkbox_col_index <- which(col_names == "human_agree")
    
    if (length(checkbox_col_index) == 0) {
      log_message("WARN", "human_agree 컬럼을 찾을 수 없습니다.")
      return(FALSE)
    }
    
    # 체크박스 적용 범위
    start_row <- 2
    end_row <- nrow(data) + 1
    checkbox_col_letter <- LETTERS[checkbox_col_index]
    checkbox_range <- sprintf("%s%d:%s%d", checkbox_col_letter, start_row, checkbox_col_letter, end_row)
    
    log_message("INFO", sprintf("체크박스 범위: %s", checkbox_range))
    
    # 방법 1: 직접 체크박스 생성 시도 (sheet_format 사용)
    tryCatch({
      log_message("INFO", "sheet_format을 사용한 체크박스 생성...")
      
      # 먼저 논리값 데이터 입력
      logical_values <- rep(FALSE, nrow(data))
      checkbox_df <- data.frame(x = logical_values)
      names(checkbox_df) <- "human_agree"
      
      range_write(
        ss = sheet_id,
        data = checkbox_df,
        sheet = "coding_data",
        range = checkbox_range,
        col_names = FALSE,
        reformat = FALSE
      )
      
      log_message("INFO", "논리값 데이터 입력 완료")
      Sys.sleep(1)
      
      # googlesheets4의 range_flood 사용해서 체크박스 설정 시도
      tryCatch({
        range_flood(
          ss = sheet_id,
          sheet = "coding_data",
          range = checkbox_range,
          cell = cell_logical(TRUE),  # 체크박스 형식 지정
          reformat = TRUE
        )
        log_message("INFO", "range_flood로 체크박스 형식 적용 완료")
      }, error = function(flood_error) {
        log_message("WARN", sprintf("range_flood 실패: %s", flood_error$message))
      })
      
      # 헤더 업데이트
      header_range <- sprintf("%s1", checkbox_col_letter)
      range_write(
        ss = sheet_id,
        data = data.frame(header = "human_agree (체크박스)"),
        sheet = "coding_data",
        range = header_range,
        col_names = FALSE
      )
      
      log_message("INFO", "🎯 체크박스 생성 시도 완료!")
      log_message("INFO", "📋 결과 확인: 시트에서 셀을 클릭해보세요")
      
      return(TRUE)
      
    }, error = function(simple_error) {
      log_message("WARN", sprintf("단순 방법 실패: %s", simple_error$message))
      
      # 방법 2: 텍스트로 FALSE 입력 + 수동 설정 안내
      tryCatch({
        log_message("INFO", "대안 방법: FALSE 텍스트 입력...")
        
        # 텍스트 "FALSE"로 입력
        text_df <- data.frame(x = rep("FALSE", nrow(data)))
        names(text_df) <- "human_agree"
        
        range_write(
          ss = sheet_id,
          data = text_df,
          sheet = "coding_data",
          range = checkbox_range,
          col_names = FALSE
        )
        
        # 헤더에 수동 설정 안내
        header_range <- sprintf("%s1", checkbox_col_letter)
        range_write(
          ss = sheet_id,
          data = data.frame(header = "human_agree (수동설정필요)"),
          sheet = "coding_data",
          range = header_range,
          col_names = FALSE
        )
        
        log_message("WARN", "⚠️ 체크박스 자동 생성 실패")
        log_message("INFO", sprintf("📍 수동 설정: %s열 선택 → 삽입 → 체크박스", checkbox_col_letter))
        log_message("INFO", "🔧 '참고사항' 시트에서 상세 설정 방법을 확인하세요")
        
        return(FALSE)
        
      }, error = function(fallback_error) {
        log_message("ERROR", sprintf("모든 방법 실패: %s", fallback_error$message))
        return(FALSE)
      })
    })
    
  }, error = function(e) {
    log_message("ERROR", sprintf("단순 체크박스 생성 중 오류: %s", e$message))
    return(FALSE)
  })
}

# 수동 체크박스 설정을 위한 준비 함수
prepare_for_manual_checkbox_setup <- function(sheet_id, data) {
  
  tryCatch({
    log_message("INFO", "수동 체크박스 설정을 위한 데이터 준비 중...")
    
    # human_agree 컬럼 위치 찾기
    col_names <- names(data)
    checkbox_col_index <- which(col_names == "human_agree")
    
    if (length(checkbox_col_index) == 0) {
      log_message("WARN", "human_agree 컬럼을 찾을 수 없습니다.")
      return(FALSE)
    }
    
    # 체크박스 적용 범위
    start_row <- 2
    end_row <- nrow(data) + 1
    checkbox_col_letter <- LETTERS[checkbox_col_index]
    checkbox_range <- sprintf("%s%d:%s%d", checkbox_col_letter, start_row, checkbox_col_letter, end_row)
    
    log_message("INFO", sprintf("체크박스 설정 대상: %s열 (%s)", checkbox_col_letter, checkbox_range))
    
    # 1단계: FALSE 값으로 명확히 설정 (수동 변환이 쉽도록)
    tryCatch({
      # 명시적 텍스트 "FALSE"로 설정
      false_values <- rep("FALSE", nrow(data))
      false_df <- data.frame(x = false_values)
      names(false_df) <- "human_agree"
      
      range_write(
        ss = sheet_id,
        data = false_df,
        sheet = "coding_data",
        range = checkbox_range,
        col_names = FALSE
      )
      
      log_message("INFO", "✅ FALSE 값으로 데이터 준비 완료")
      
    }, error = function(e) {
      log_message("WARN", sprintf("데이터 준비 실패: %s", e$message))
    })
    
    # 2단계: 헤더에 수동 설정 안내 추가
    tryCatch({
      header_range <- sprintf("%s1", checkbox_col_letter)
      header_text <- sprintf("human_agree (수동설정: %s열선택→삽입→체크박스)", checkbox_col_letter)
      
      range_write(
        ss = sheet_id,
        data = data.frame(header = header_text),
        sheet = "coding_data",
        range = header_range,
        col_names = FALSE
      )
      
      log_message("INFO", "✅ 헤더에 수동 설정 안내 추가 완료")
      
    }, error = function(e) {
      log_message("WARN", sprintf("헤더 업데이트 실패: %s", e$message))
    })
    
    log_message("INFO", "🔧 수동 체크박스 설정 준비 완료")
    log_message("INFO", sprintf("📍 설정 방법: %s열 전체 선택 → 삽입 → 체크박스", checkbox_col_letter))
    
    return(TRUE)
    
  }, error = function(e) {
    log_message("ERROR", sprintf("수동 체크박스 준비 중 오류: %s", e$message))
    return(FALSE)
  })
}

# 로컬 CSV 파일 생성 함수 (구글 시트 실패 시 대안)
create_local_coding_files <- function(coding_data, sample_label, timestamp) {
  
  tryCatch({
    # 디렉토리 생성
    local_dir <- "results/human_coding_local"
    if (!dir.exists(local_dir)) {
      dir.create(local_dir, recursive = TRUE)
      log_message("INFO", sprintf("디렉토리 생성: %s", local_dir))
    }
    
    # 코더별 파일 생성
    num_coders <- HUMAN_CODING_CONFIG$num_coders
    created_files <- character()
    
    for (i in 1:num_coders) {
      filename <- sprintf("%s/human_coding_%s_coder_%d_%s.csv", 
                         local_dir, sample_label, i, timestamp)
      
      # CSV 파일로 저장
      write.csv(coding_data, filename, row.names = FALSE, fileEncoding = "UTF-8")
      created_files <- c(created_files, filename)
      
      log_message("INFO", sprintf("✅ 코더 %d 파일 생성: %s", i, filename))
    }
    
    # 사용 안내 파일 생성
    readme_file <- sprintf("%s/README_인간코딩안내_%s.txt", local_dir, timestamp)
    readme_content <- sprintf("
=== 인간 코딩 안내 (%s) ===

📋 생성된 파일:
%s

📝 코딩 방법:
1. 각 코더는 해당 번호의 CSV 파일을 사용
2. 'human_agree' 컬럼에 동의하는 항목은 TRUE, 동의하지 않는 항목은 FALSE 입력
3. 완료 후 파일을 원래 이름 그대로 저장

💾 제출 방법:
1. 완료된 파일을 %s 폴더에 저장
2. 파일명은 변경하지 말 것
3. 분석 스크립트가 자동으로 인식하여 처리

⚠️ 주의사항:
- 파일 인코딩을 UTF-8로 유지
- 컬럼 구조 변경 금지
- human_agree 컬럼만 수정

📞 문의: 시스템 관리자
생성시간: %s
", sample_label, paste(created_files, collapse = "\n"), local_dir, timestamp)
    
    writeLines(readme_content, readme_file, useBytes = TRUE)
    log_message("INFO", sprintf("📖 사용 안내 파일 생성: %s", readme_file))
    
    # 결과 요약 출력
    cat("\n", rep("=", 60), "\n")
    cat("🔄 대안: 로컬 CSV 파일 생성 완료\n")
    cat(rep("=", 60), "\n")
    cat(sprintf("📁 저장 위치: %s\n", local_dir))
    cat(sprintf("📊 생성된 파일: %d개\n", length(created_files)))
    cat(sprintf("👥 코더 수: %d명\n", num_coders))
    cat(sprintf("📋 데이터 행수: %d개\n", nrow(coding_data)))
    cat(sprintf("📖 사용 안내: %s\n", basename(readme_file)))
    cat("\n💡 이 파일들을 사용하여 오프라인으로 인간 코딩을 진행할 수 있습니다.\n")
    cat("완료 후 같은 폴더에 저장하시면 분석 스크립트가 자동 인식합니다.\n")
    cat(rep("=", 60), "\n\n")
    
    return(TRUE)
    
  }, error = function(e) {
    log_message("ERROR", sprintf("로컬 CSV 파일 생성 실패: %s", e$message))
    return(FALSE)
  })
}