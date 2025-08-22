# 프롬프트 일관성 테스트
# config.R의 PROMPT_CONFIG와 functions.R의 기본값이 일치하는지 확인

cat("🧪 프롬프트 일관성 테스트\n")
cat(rep("=", 50), "\n")

# 1. config.R 로드 (필수)
cat("1️⃣ config.R 로드 중...\n")
tryCatch({
  source("../libs/config.R")
  cat("✅ config.R 로드 완료\n")
}, error = function(e) {
  cat("❌ config.R 로드 실패:", e$message, "\n")
  stop("config.R을 확인해주세요")
})

cat("2️⃣ functions.R 로드 중...\n")
tryCatch({
  source("../libs/functions.R")
  cat("✅ functions.R 로드 완료\n")
}, error = function(e) {
  cat("❌ functions.R 로드 실패:", e$message, "\n")
  stop("functions.R을 확인해주세요")
})

cat("3️⃣ PROMPT_CONFIG 확인\n")
if (exists("PROMPT_CONFIG")) {
  cat("✅ PROMPT_CONFIG 정상 로드됨\n")
  config_prompt <- PROMPT_CONFIG$base_instructions
  cat("설정 프롬프트 시작:", substr(config_prompt, 1, 50), "...\n")
} else {
  cat("❌ PROMPT_CONFIG 없음\n")
  stop("config.R에서 PROMPT_CONFIG를 정의해주세요")
}

cat("\n4️⃣ 프롬프트 생성 함수 테스트\n")

# 테스트 데이터
test_text <- "테스트 댓글입니다."
test_context <- "테스트 게시글 내용"
test_title <- "테스트 제목"

# 프롬프트 생성
generated_prompt <- create_analysis_prompt(
  text = test_text,
  구분 = "댓글", 
  context = test_context,
  context_title = test_title
)

cat("생성된 프롬프트 시작:", substr(generated_prompt, 1, 100), "...\n")
cat("생성된 프롬프트 길이:", nchar(generated_prompt), "자\n")

# 주요 키워드 확인
keywords <- c("리서치 보조원", "플루치크", "PAD", "기쁨", "신뢰", "교사 커뮤니티")
cat("\n5️⃣ 핵심 키워드 포함 확인\n")
for (keyword in keywords) {
  if (grepl(keyword, generated_prompt)) {
    cat("✅", keyword, "포함\n")
  } else {
    cat("❌", keyword, "누락\n")
  }
}

cat("\n🎯 프롬프트 업데이트 확인 방법:\n")
cat("1. 01_data_loading_and_prompt_generation.R 실행\n")
cat("2. 새로 생성된 data/prompts_ready.RDS 확인\n") 
cat("3. 04 스크립트로 배치 분석 실행\n")
cat("4. CSV 결과에서 prompt 컬럼이 올바른지 확인\n")

cat(rep("=", 50), "\n")
cat("🧪 테스트 완료\n")