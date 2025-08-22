# 인간 코딩 시스템 준비 상태 테스트

cat("🔍 인간 코딩 시스템 준비 상태 점검...\n\n")

# 1. 필수 파일 존재 확인
required_files <- c(
  "config.R",
  "utils.R", 
  "human_coding.R",
  "05_reliability_analysis.R",
  "03_full_emotion_analysis.R"
)

cat("📁 필수 파일 체크:\n")
for (file in required_files) {
  if (file.exists(file)) {
    cat(sprintf("  ✅ %s\n", file))
  } else {
    cat(sprintf("  ❌ %s - 파일 없음!\n", file))
  }
}

# 2. 설정 로드 테스트
cat("\n⚙️ 설정 로드 테스트:\n")
tryCatch({
  source("config.R")
  cat("  ✅ config.R 로드 성공\n")
  
  if (exists("HUMAN_CODING_CONFIG")) {
    cat("  ✅ HUMAN_CODING_CONFIG 존재\n")
    cat(sprintf("  📊 코더 수: %d명\n", HUMAN_CODING_CONFIG$num_coders))
    cat(sprintf("  📊 최소 샘플: %d개\n", HUMAN_CODING_CONFIG$min_sample_size))
  } else {
    cat("  ❌ HUMAN_CODING_CONFIG 없음!\n")
  }
}, error = function(e) {
  cat(sprintf("  ❌ config.R 로드 실패: %s\n", e$message))
})

# 3. 함수 로드 테스트
cat("\n🔧 함수 로드 테스트:\n")
tryCatch({
  source("utils.R")
  cat("  ✅ utils.R 로드 성공\n")
  
  source("human_coding.R")
  cat("  ✅ human_coding.R 로드 성공\n")
  
  # 핵심 함수 존재 확인
  essential_functions <- c(
    "create_human_coding_sheets",
    "extract_sheet_id",
    "%||%"
  )
  
  for (func in essential_functions) {
    if (exists(func)) {
      cat(sprintf("  ✅ %s 함수 존재\n", func))
    } else {
      cat(sprintf("  ❌ %s 함수 없음!\n", func))
    }
  }
  
}, error = function(e) {
  cat(sprintf("  ❌ 함수 로드 실패: %s\n", e$message))
})

# 4. 패키지 확인
cat("\n📦 필수 패키지 체크:\n")
required_packages <- c("dplyr", "googlesheets4", "googledrive", "readr", "irr", "httr2")

for (pkg in required_packages) {
  if (pkg %in% installed.packages()[,"Package"]) {
    cat(sprintf("  ✅ %s 설치됨\n", pkg))
  } else {
    cat(sprintf("  ⚠️ %s 미설치 - 자동 설치 예정\n", pkg))
  }
}

# 5. 폴더 구조 확인
cat("\n📂 폴더 구조 체크:\n")
required_dirs <- c("results", "data")

for (dir in required_dirs) {
  if (dir.exists(dir)) {
    cat(sprintf("  ✅ %s 폴더 존재\n", dir))
  } else {
    cat(sprintf("  ⚠️ %s 폴더 없음 - 자동 생성됨\n", dir))
  }
}

# 6. 데이터 파일 확인
cat("\n💾 데이터 파일 체크:\n")
if (file.exists("data/prompts_ready.RDS")) {
  cat("  ✅ prompts_ready.RDS 존재\n")
  
  tryCatch({
    test_data <- readRDS("data/prompts_ready.RDS")
    cat(sprintf("  📊 데이터 행수: %d개\n", nrow(test_data)))
    
    if (nrow(test_data) >= HUMAN_CODING_CONFIG$min_sample_size) {
      cat("  ✅ 최소 샘플 크기 충족\n")
    } else {
      cat("  ⚠️ 샘플 크기 부족\n")
    }
  }, error = function(e) {
    cat(sprintf("  ❌ 데이터 읽기 실패: %s\n", e$message))
  })
} else {
  cat("  ❌ prompts_ready.RDS 없음 - 먼저 01_데이터_불러오기_프롬프트_생성.R 실행 필요\n")
}

# 7. 최종 판정
cat("\n" , rep("=", 50), "\n")
cat("🎯 최종 판정:\n")

if (all(file.exists(required_files)) && 
    exists("HUMAN_CODING_CONFIG") && 
    exists("create_human_coding_sheets")) {
  
  cat("✅ 시스템 준비 완료!\n\n")
  cat("🚀 실행 방법:\n")
  cat("1. source(\"03_full_emotion_analysis.R\") - 샘플 분석 + 구글 시트 생성\n")
  cat("2. 4명 코더가 구글 시트에서 작업\n") 
  cat("3. source(\"05_reliability_analysis.R\") - Krippendorff's Alpha 계산\n\n")
  
} else {
  cat("❌ 시스템 준비 미완료\n")
  cat("위에 표시된 문제점들을 해결해주세요.\n\n")
}

cat(rep("=", 50), "\n")