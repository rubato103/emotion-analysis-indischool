# MCP (Model Context Protocol) 자동화 스크립트
# 목적: Qwen Code와의 상호작용을 자동화하여 반복적 작업을 효율화
# 작성자: 자동 생성 (Qwen Code)
# 날짜: 2025-08-28

#' MCP 자동화 클래스
MCPAutomator <- R6::R6Class(\"MCPAutomator\",
  public = list(
    # 속성
    project_path = NULL,
    log_level = \"INFO\",
    enable_notifications = TRUE,
    
    # 초기화
    initialize = function(project_path = getwd(), log_level = \"INFO\") {
      self$project_path <- normalizePath(project_path)
      self$log_level <- log_level
      self$setup_logging()
      self$log_message(\"INFO\", \"MCP 자동화 시스템 초기화 완료\")
    },
    
    # 로깅 설정
    setup_logging = function() {
      log_file <- file.path(self$project_path, \"logs\", \"mcp_automation.log\")
      if (!dir.exists(dirname(log_file))) {
        dir.create(dirname(log_file), recursive = TRUE)
      }
      # 로그 파일이 너무 커지지 않도록 관리
      if (file.exists(log_file) && file.size(log_file) > 10*1024*1024) { # 10MB
        file.rename(log_file, paste0(log_file, \"_old\"))
      }
    },
    
    # 로그 메시지
    log_message = function(level, message) {
      if (self$should_log(level)) {
        timestamp <- format(Sys.time(), \"%Y-%m-%d %H:%M:%S\")
        log_entry <- sprintf(\"[%s] [%s] %s
\", timestamp, level, message)
        cat(log_entry)
        
        # 파일에도 로그 저장
        log_file <- file.path(self$project_path, \"logs\", \"mcp_automation.log\")
        cat(log_entry, file = log_file, append = TRUE)
        
        # 시스템 알림 (중요한 메시지만)
        if (self$enable_notifications && level %in% c(\"ERROR\", \"WARN\")) {
          self$send_notification(message)
        }
      }
    },
    
    # 로그 레벨 확인
    should_log = function(level) {
      levels <- c(\"DEBUG\", \"INFO\", \"WARN\", \"ERROR\")
      current_level_idx <- which(levels == self$log_level)
      message_level_idx <- which(levels == level)
      return(length(message_level_idx) > 0 && message_level_idx >= current_level_idx)
    },
    
    # 시스템 알림
    send_notification = function(message) {
      # 간단한 시스템 알림 (Windows의 경우)
      if (.Platform$OS.type == \"windows\") {
        system(sprintf('powershell -Command \"New-BurntToastNotification -Text 'MCP Automation', '%s'\"', message))
      }
    },
    
    # 프로젝트 상태 분석
    analyze_project_state = function() {
      self$log_message(\"INFO\", \"프로젝트 상태 분석 시작\")
      
      # 프로젝트 구조 분석
      project_files <- list.files(self$project_path, recursive = TRUE, include.dirs = FALSE)
      
      # 주요 파일 타입 통계
      file_extensions <- tools::file_ext(project_files)
      file_stats <- table(file_extensions)
      
      # R 파일 분석
      r_files <- grep(\"\\\\.R$\", project_files, value = TRUE)
      r_file_count <- length(r_files)
      
      # 데이터 파일 분석
      data_files <- grep(\"\\\\.(csv|parquet|RDS|rds)$\", project_files, value = TRUE)
      data_file_count <- length(data_files)
      
      # 결과 파일 분석
      result_files <- grep(\"\\\\.(json|csv|RDS|rds)$\", list.files(file.path(self$project_path, \"results\"), recursive = TRUE), value = TRUE)
      result_file_count <- length(result_files)
      
      state_info <- list(
        total_files = length(project_files),
        r_files = r_file_count,
        data_files = data_file_count,
        result_files = result_file_count,
        file_types = as.list(file_stats)
      )
      
      self$log_message(\"INFO\", sprintf(\"프로젝트 상태: 총 %d개 파일, R파일 %d개, 데이터파일 %d개, 결과파일 %d개\", 
                                     state_info$total_files, state_info$r_files, 
                                     state_info$data_files, state_info$result_files))
      
      return(state_info)
    },
    
    # 자동화된 코드 리뷰
    auto_code_review = function() {
      self$log_message(\"INFO\", \"자동 코드 리뷰 시작\")
      
      # R 파일 찾기
      r_files <- list.files(self$project_path, pattern = \"\\\\.R$\", recursive = TRUE, full.names = TRUE)
      
      review_results <- list()
      
      for (r_file in r_files) {
        # 파일 이름에서 경로 제거
        file_name <- basename(r_file)
        
        # 파일 읽기
        content <- readLines(r_file, warn = FALSE)
        
        # 코드 품질 검사
        issues <- list()
        
        # 1. TODO/FIXME 주석 확인
        todo_lines <- grep(\"(TODO|FIXME)\", content, ignore.case = TRUE)
        if (length(todo_lines) > 0) {
          issues$todo_comments <- paste(\"라인\", paste(todo_lines, collapse = \", \"))
        }
        
        # 2. 긴 라인 확인 (120자 이상)
        long_lines <- which(nchar(content) > 120)
        if (length(long_lines) > 0) {
          issues$long_lines <- paste(\"라인\", paste(head(long_lines, 5), collapse = \", \"), 
                                   ifelse(length(long_lines) > 5, \"외 더 있음\", \"\"))
        }
        
        # 3. 빈 라인 과다 사용 확인 (연속 3개 이상)
        consecutive_blanks <- which(diff(c(0, which(content == \"\"), length(content)+1)) > 3)
        if (length(consecutive_blanks) > 0) {
          issues$consecutive_blanks <- paste(\"위치\", paste(head(consecutive_blanks, 3), collapse = \", \"), 
                                           ifelse(length(consecutive_blanks) > 3, \"외 더 있음\", \"\"))
        }
        
        # 4. library() 호출 확인 (순서 및 중복)
        library_calls <- grep(\"^\\\\s*library\\(\", content)
        if (length(library_calls) > 0) {
          libraries <- sapply(library_calls, function(i) {
            line <- content[i]
            gsub(\"^\\\\s*library\\(([^)]+)\\).*\", \"\\\\1\", line)
          })
          
          # 중복 라이브러리 확인
          dup_libraries <- unique(libraries[duplicated(libraries)])
          if (length(dup_libraries) > 0) {
            issues$duplicate_libraries <- paste(dup_libraries, collapse = \", \")
          }
        }
        
        # 결과 저장
        if (length(issues) > 0) {
          review_results[[file_name]] <- issues
        }
      }
      
      # 결과 요약
      if (length(review_results) > 0) {
        self$log_message(\"WARN\", sprintf(\"코드 리뷰 결과: %d개 파일에서 문제 발견\", length(review_results)))
        for (file_name in names(review_results)) {
          issues <- review_results[[file_name]]
          issue_desc <- paste(names(issues), collapse = \", \")
          self$log_message(\"WARN\", sprintf(\"  %s: %s\", file_name, issue_desc))
        }
      } else {
        self$log_message(\"INFO\", \"코드 리뷰 완료: 문제 없음\")
      }
      
      return(review_results)
    },
    
    # 자동화된 데이터 품질 검사
    auto_data_quality_check = function() {
      self$log_message(\"INFO\", \"데이터 품질 검사 시작\")
      
      # 데이터 디렉토리 확인
      data_dir <- file.path(self$project_path, \"data\")
      if (!dir.exists(data_dir)) {
        self$log_message(\"WARN\", \"데이터 디렉토리 없음\")
        return(list())
      }
      
      # 데이터 파일 찾기
      data_files <- list.files(data_dir, pattern = \"\\\\.(csv|parquet)$\", full.names = TRUE)
      
      quality_results <- list()
      
      for (data_file in data_files) {
        file_name <- basename(data_file)
        file_ext <- tools::file_ext(data_file)
        
        tryCatch({
          # 파일 읽기
          if (file_ext == \"csv\") {
            df <- read.csv(data_file, stringsAsFactors = FALSE, nrows = 1000) # 샘플만 읽기
          } else if (file_ext == \"parquet\") {
            # arrow 패키지가 필요함
            if (requireNamespace(\"arrow\", quietly = TRUE)) {
              df <- arrow::read_parquet(data_file, as_data_frame = TRUE)
            } else {
              self$log_message(\"WARN\", sprintf(\"%s: arrow 패키지 필요\", file_name))
              next
            }
          }
          
          # 품질 검사
          checks <- list(
            rows = nrow(df),
            cols = ncol(df),
            missing_values = sum(is.na(df)),
            empty_strings = sum(df == \"\", na.rm = TRUE),
            duplicated_rows = sum(duplicated(df))
          )
          
          quality_results[[file_name]] <- checks
          
          self$log_message(\"INFO\", sprintf(\"%s: %d행 %d열, 누락값 %d개, 빈문자열 %d개, 중복행 %d개\", 
                                         file_name, checks$rows, checks$cols, 
                                         checks$missing_values, checks$empty_strings, 
                                         checks$duplicated_rows))
        }, error = function(e) {
          self$log_message(\"ERROR\", sprintf(\"%s 처리 중 오류: %s\", file_name, e$message))
        })
      }
      
      return(quality_results)
    },
    
    # 자동화된 결과 모니터링
    monitor_results = function() {
      self$log_message(\"INFO\", \"결과 모니터링 시작\")
      
      # 결과 디렉토리 확인
      results_dir <- file.path(self$project_path, \"results\")
      if (!dir.exists(results_dir)) {
        self$log_message(\"WARN\", \"결과 디렉토리 없음\")
        return(list())
      }
      
      # 최신 결과 파일 찾기
      result_files <- list.files(results_dir, pattern = \"\\\\.(json|RDS|rds)$\", full.names = TRUE)
      if (length(result_files) == 0) {
        self$log_message(\"INFO\", \"결과 파일 없음\")
        return(list())
      }
      
      # 수정 시간 기준으로 정렬
      file_info <- file.info(result_files)
      latest_file <- rownames(file_info)[which.max(file_info$mtime)]
      
      self$log_message(\"INFO\", sprintf(\"최신 결과 파일: %s (%s)\", 
                                     basename(latest_file), 
                                     format(file_info[latest_file, \"mtime\"], \"%Y-%m-%d %H:%M:%S\")))
      
      return(list(
        latest_file = latest_file,
        latest_time = file_info[latest_file, \"mtime\"],
        total_files = length(result_files)
      ))
    },
    
    # 자동화된 백업
    auto_backup = function(backup_dir = NULL) {
      self$log_message(\"INFO\", \"자동 백업 시작\")
      
      # 백업 디렉토리 설정
      if (is.null(backup_dir)) {
        backup_dir <- file.path(self$project_path, \"backups\")
      }
      
      if (!dir.exists(backup_dir)) {
        dir.create(backup_dir, recursive = TRUE)
      }
      
      # 백업 이름 생성
      timestamp <- format(Sys.time(), \"%Y%m%d_%H%M%S\")
      backup_name <- sprintf(\"project_backup_%s.zip\", timestamp)
      backup_path <- file.path(backup_dir, backup_name)
      
      # 중요한 디렉토리만 백업
      important_dirs <- c(\"data\", \"results\", \"modules\", \"libs\")
      files_to_backup <- c()
      
      for (dir_name in important_dirs) {
        dir_path <- file.path(self$project_path, dir_name)
        if (dir.exists(dir_path)) {
          files <- list.files(dir_path, recursive = TRUE, full.names = TRUE)
          files_to_backup <- c(files_to_backup, files)
        }
      }
      
      # 주요 R 스크립트 추가
      main_scripts <- list.files(self$project_path, pattern = \"^[0-9]{2}_.*\\\\.R$\", full.names = TRUE)
      files_to_backup <- c(files_to_backup, main_scripts)
      
      if (length(files_to_backup) > 0) {
        # 백업 생성 (Windows에서 zip 사용)
        if (.Platform$OS.type == \"windows\") {
          # 상대 경로로 변환
          rel_files <- sub(paste0(\"^\", self$project_path, \"/?\"), \"\", files_to_backup)
          # zip 명령어 실행
          zip_cmd <- sprintf('powershell -Command \"Compress-Archive -Path %s -DestinationPath %s -Force\"', 
                           paste(sprintf(\"'%s'\", rel_files), collapse = \",\"), 
                           shQuote(backup_path))
          system(zip_cmd)
        }
        
        self$log_message(\"INFO\", sprintf(\"백업 완료: %s\", backup_path))
        return(backup_path)
      } else {
        self$log_message(\"WARN\", \"백업할 파일 없음\")
        return(NULL)
      }
    },
    
    # 전체 자동화 실행
    run_full_automation = function() {
      self$log_message(\"INFO\", \"=== 전체 자동화 프로세스 시작 ===\")
      
      # 1. 프로젝트 상태 분석
      state <- self$analyze_project_state()
      
      # 2. 코드 리뷰
      review_results <- self$auto_code_review()
      
      # 3. 데이터 품질 검사
      quality_results <- self$auto_data_quality_check()
      
      # 4. 결과 모니터링
      monitor_results <- self$monitor_results()
      
      # 5. 자동 백업 (주기적으로만 실행)
      # self$auto_backup()
      
      self$log_message(\"INFO\", \"=== 전체 자동화 프로세스 완료 ===\")
      
      return(list(
        project_state = state,
        code_review = review_results,
        data_quality = quality_results,
        results_monitor = monitor_results
      ))
    }
  )
)

# 간단한 사용 예제
run_mcp_automation <- function() {
  # 자동화 시스템 초기화
  automator <- MCPAutomator$new()
  
  # 전체 자동화 실행
  results <- automator$run_full_automation()
  
  return(results)
}

# 대화형 모드에서 자동 실행
if (interactive()) {
  cat(\"🚀 MCP 자동화 시스템을 시작합니다...
\")
  automation_results <- run_mcp_automation()
  cat(\"✅ MCP 자동화 완료
\")
}