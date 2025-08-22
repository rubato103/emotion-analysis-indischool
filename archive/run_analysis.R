# 감정분석 메인 실행 스크립트
# 전체 파이프라인을 통합 관리

# 설정 및 유틸리티 로드
source("config.R")
source("utils.R")

# 필수 패키지 로드
required_packages <- c("dplyr", "stringr", "jsonlite", "crayon")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  install.packages(new_packages)
}
lapply(required_packages, library, character.only = TRUE)

# 메인 실행 함수
run_emotion_analysis <- function(skip_setup = TRUE, 
                                run_test = TRUE, 
                                run_full_analysis = TRUE,
                                force_restart = FALSE) {
  
  log_message("INFO", "=== 감정분석 파이프라인 시작 ===")
  
  # 진행상황 추적기 생성
  total_steps <- sum(!skip_setup, TRUE, run_test, run_full_analysis)
  progress <- create_progress_tracker(total_steps, "MAIN")
  
  tryCatch({
    # 1. 환경 설정 (선택사항)
    if (!skip_setup) {
      progress$update("환경 설정")
      source("00_setup_r_environment.R")
    }
    
    # 2. 데이터 로드 및 프롬프트 생성
    progress$update("데이터 전처리")
    
    # 체크포인트 확인
    if (!force_restart) {
      checkpoint_data <- load_checkpoint("processed_data", "01_data_loading")
      if (!is.null(checkpoint_data)) {
        log_message("INFO", "기존 전처리 데이터를 사용합니다.")
      } else {
        source("01_데이터_불러오기_프롬프트_생성.R")
      }
    } else {
      source("01_데이터_불러오기_프롬프트_생성.R")
    }
    
    # 3. 단건 테스트 (선택사항)
    if (run_test) {
      progress$update("단건 테스트")
      log_message("INFO", "API 연결 테스트를 실행합니다...")
      
      test_result <- tryCatch({
        source("02_단건분석_테스트.R")
        TRUE
      }, error = function(e) {
        log_message("ERROR", sprintf("단건 테스트 실패: %s", e$message))
        FALSE
      })
      
      if (!test_result) {
        stop("단건 테스트 실패로 전체 분석을 중단합니다.")
      }
    }
    
    # 4. 전체 분석 실행 (선택사항)
    if (run_full_analysis) {
      progress$update("전체 분석 실행")
      
      # 분석 규모 확인
      prompts_data <- readRDS(PATHS$prompts_data)
      expected_calls <- if (ANALYSIS_CONFIG$sample_post_count > 0) {
        prompts_data %>% 
          filter(post_id %in% sample(unique(prompts_data$post_id), 
                                   min(ANALYSIS_CONFIG$sample_post_count, 
                                       length(unique(prompts_data$post_id))))) %>%
          nrow()
      } else {
        nrow(prompts_data)
      }
      
      estimated_time <- expected_calls / API_CONFIG$rate_limit_per_minute
      log_message("INFO", sprintf("예상 API 호출: %d회, 소요시간: %.1f분", 
                                 expected_calls, estimated_time))
      
      # 사용자 확인 (인터랙티브 모드일 때만)
      if (interactive()) {
        response <- readline(prompt = "전체 분석을 계속하시겠습니까? (y/n): ")
        if (tolower(response) != "y") {
          log_message("INFO", "사용자가 전체 분석을 취소했습니다.")
          return(invisible(NULL))
        }
      }
      
      source("03_감정분석_전체실행.R")
    }
    
    log_message("INFO", "=== 감정분석 파이프라인 완료 ===")
    
  }, error = function(e) {
    log_message("ERROR", sprintf("파이프라인 실행 중 오류 발생: %s", e$message))
    stop(e)
  })
}

# 빠른 실행 함수들
run_quick_test <- function() {
  run_emotion_analysis(skip_setup = TRUE, run_test = TRUE, run_full_analysis = FALSE)
}

run_full_pipeline <- function() {
  run_emotion_analysis(skip_setup = TRUE, run_test = TRUE, run_full_analysis = TRUE)
}

run_data_prep_only <- function() {
  run_emotion_analysis(skip_setup = TRUE, run_test = FALSE, run_full_analysis = FALSE)
}

# 스크립트 직접 실행 시
if (!interactive()) {
  # 명령줄 인자 파싱
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) == 0 || args[1] == "full") {
    run_full_pipeline()
  } else if (args[1] == "test") {
    run_quick_test()  
  } else if (args[1] == "prep") {
    run_data_prep_only()
  } else {
    cat("사용법: Rscript run_analysis.R [full|test|prep]\n")
  }
}