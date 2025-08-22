# 배치 API 연결 테스트 스크립트
# 목적: Gemini API 배치 기능 연결 확인 및 간단한 테스트

# 설정 로드
source("config.R")
source("utils.R")

# 필요한 패키지
required_packages <- c("httr2", "jsonlite")
lapply(required_packages, library, character.only = TRUE)

# API 키 확인
api_key <- Sys.getenv("GEMINI_API_KEY")
if (api_key == "") {
  stop("⚠️ GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
}

cat("🔑 API 키 확인: ✅\n")

# 배치 API 테스트 함수
test_batch_api <- function() {
  
  cat("=== Gemini 배치 API 연결 테스트 ===\n")
  
  # 1. 인라인 요청으로 간단한 배치 테스트
  cat("1. 인라인 배치 요청 테스트...\n")
  
  # 정확한 배치 요청 형식 (Google 문서 기준)
  batch_request <- list(
    batch = list(
      display_name = sprintf("test_batch_%s", format(Sys.time(), "%Y%m%d_%H%M%S")),
      input_config = list(
        requests = list(
          requests = list(
            list(
              request = list(
                contents = list(
                  list(
                    parts = list(
                      list(text = "안녕하세요를 영어로 번역해주세요.")
                    )
                  )
                )
              ),
              metadata = list(key = "request-1")
            ),
            list(
              request = list(
                contents = list(
                  list(
                    parts = list(
                      list(text = "감사합니다를 영어로 번역해주세요.")
                    )
                  )
                )
              ),
              metadata = list(key = "request-2")
            )
          )
        )
      )
    )
  )
  
  # 요청 내용 디버깅
  cat("🔍 요청 내용 확인:\n")
  request_json <- jsonlite::toJSON(batch_request, auto_unbox = TRUE, pretty = TRUE)
  cat(substr(request_json, 1, 500), "...\n")
  
  tryCatch({
    # API 호출
    response <- httr2::request("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:batchGenerateContent") %>%
      httr2::req_headers(
        `x-goog-api-key` = api_key,
        `Content-Type` = "application/json"
      ) %>%
      httr2::req_body_json(batch_request) %>%
      httr2::req_perform()
    
    batch_result <- httr2::resp_body_json(response)
    
    cat("✅ 배치 작업 생성 성공!\n")
    cat(sprintf("📋 작업 이름: %s\n", batch_result$name))
    
    return(batch_result$name)
    
  }, error = function(e) {
    cat(sprintf("❌ 배치 API 테스트 실패: %s\n", e$message))
    
    # 상세 오류 정보 출력
    if (exists("response")) {
      tryCatch({
        error_content <- httr2::resp_body_string(response)
        cat("🔍 오류 상세:\n")
        cat(error_content, "\n")
        
        # JSON 파싱 시도
        error_json <- jsonlite::fromJSON(error_content)
        if (!is.null(error_json$error)) {
          cat(sprintf("코드: %s\n", error_json$error$code))
          cat(sprintf("메시지: %s\n", error_json$error$message))
        }
      }, error = function(e2) {
        cat("오류 내용을 파싱할 수 없습니다.\n")
      })
    }
    
    return(NULL)
  })
}

# 배치 작업 상태 확인 함수
check_batch_status <- function(batch_name) {
  if (is.null(batch_name)) {
    cat("❌ 유효하지 않은 배치 이름입니다.\n")
    return(NULL)
  }
  
  cat(sprintf("📊 배치 상태 확인: %s\n", batch_name))
  
  tryCatch({
    response <- httr2::request(sprintf("https://generativelanguage.googleapis.com/v1beta/%s", batch_name)) %>%
      httr2::req_headers(`x-goog-api-key` = api_key) %>%
      httr2::req_perform()
    
    batch_status <- httr2::resp_body_json(response)
    
    cat(sprintf("상태: %s\n", batch_status$metadata$state))
    cat(sprintf("생성일: %s\n", batch_status$metadata$create_time))
    
    if (!is.null(batch_status$metadata$update_time)) {
      cat(sprintf("수정일: %s\n", batch_status$metadata$update_time))
    }
    
    return(batch_status)
    
  }, error = function(e) {
    cat(sprintf("❌ 상태 확인 실패: %s\n", e$message))
    return(NULL)
  })
}

# 메인 테스트 실행
cat("🚀 Gemini 배치 API 테스트를 시작합니다...\n\n")

# 배치 API 테스트
batch_name <- test_batch_api()

if (!is.null(batch_name)) {
  cat("\n⏳ 잠시 후 상태를 확인합니다...\n")
  Sys.sleep(5)
  
  # 상태 확인
  batch_status <- check_batch_status(batch_name)
  
  if (!is.null(batch_status)) {
    cat("\n✅ 배치 API 기본 연결 테스트 성공!\n")
    cat("📋 다음 단계:\n")
    cat("1. 상태가 'JOB_STATE_SUCCEEDED'가 될 때까지 대기\n")
    cat("2. batch_monitor.R로 상태 모니터링 가능\n")
    cat(sprintf("3. 배치 이름: %s\n", batch_name))
    
    # 간단한 모니터링 제안
    cat("\n💡 지속적인 모니터링을 원한다면:\n")
    cat('source("batch_monitor.R")\n')
    cat('monitor <- BatchMonitor$new()\n')
    cat(sprintf('monitor$get_batch_status("%s")\n', batch_name))
  }
} else {
  cat("\n❌ 배치 API 테스트에 실패했습니다.\n")
  cat("🔧 문제 해결 방법:\n")
  cat("1. API 키 확인: Sys.getenv('GEMINI_API_KEY')\n")
  cat("2. 네트워크 연결 확인\n")
  cat("3. Gemini API 배치 기능 활성화 여부 확인\n")
}

cat("\n=== 테스트 완료 ===\n")