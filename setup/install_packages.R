# 필수 패키지 설치 스크립트

# 작업 디렉토리 설정
setwd("C:/Users/rubat/SynologyDrive/R_project/emotion-analysis-indischool")

# 로그 파일 설정
log_file <- "install_log.txt"
cat("패키지 설치 시작:", as.character(Sys.time()), "\n", file = log_file)

# 미러 설정
options(repos = "https://cran.seoul.go.kr/")

# 설치할 패키지 목록
packages_to_install <- c("glue", "httr2", "openai", "gemini.R", "readr", "dplyr", "jsonlite")

for (pkg in packages_to_install) {
  cat("설치 중:", pkg, "\n", file = log_file, append = TRUE)
  
  # 기존 패키지 제거
  if (pkg %in% rownames(installed.packages())) {
    try(remove.packages(pkg), silent = TRUE)
  }
  
  # 새로 설치
  try({
    install.packages(pkg, dependencies = TRUE, repos = "https://cran.seoul.go.kr/")
    cat("✓ 설치 성공:", pkg, "\n", file = log_file, append = TRUE)
  }, silent = FALSE)
  
  # 로드 테스트
  try({
    library(pkg, character.only = TRUE)
    cat("✓ 로드 성공:", pkg, "\n", file = log_file, append = TRUE)
  }, silent = FALSE)
}

cat("설치 완료:", as.character(Sys.time()), "\n", file = log_file, append = TRUE)
print("Installation script completed")