# 데이터 불러오기 및 프롬프트 생성
# 목적: CSV 데이터를 불러오고 API 요청용 프롬프트 생성, RDS 저장

# 설정 및 함수 로드
source("libs/config.R")
source("libs/functions.R", encoding = "UTF-8")
# 1. 패키지 로드
required_packages <- c("dplyr", "purrr", "readr")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {
  cat("▶️ 다음 패키지를 새로 설치합니다:", paste(new_packages, collapse = ", "), "\n")
  install.packages(new_packages)
}
lapply(required_packages, library, character.only = TRUE)
cat("✅ 패키지 로드 완료\n\n")

# 2. 데이터 로드
if (file.exists("data/data_collection.csv")) {
  corpus_df <- read_csv("data/data_collection.csv", col_types = cols(.default = "c"))
  # 숫자 컬럼 변환
  corpus_df <- corpus_df %>%
    mutate(across(c(post_id, comment_id, depth, views, likes), as.numeric))
  cat("✅ 데이터 로드 완료\n")
} else {
  stop("⚠️ 'data/data_collection.csv' 파일을 찾을 수 없습니다.")
}

# 3. 프롬프트 생성
# 게시글 제목/내용 추출
posts_lookup <- corpus_df %>%
  filter(구분 == "게시글") %>%
  select(post_id, post_title = title, post_context = content)

# 프롬프트 컬럼 추가
corpus_with_prompts <- corpus_df %>%
  left_join(posts_lookup, by = "post_id") %>%
  mutate(
    # 구분 인자 전달
    prompt = purrr::pmap_chr(
      list(
        text = content,
        구분 = 구분,
        title = if_else(구분 == "게시글", title, NA_character_),
        context = post_context,
        context_title = post_title
      ),
      create_analysis_prompt
    )
  ) %>%
  select(-post_context, -post_title)

# 4. RDS 저장
saveRDS(corpus_with_prompts, file = "data/prompts_ready.RDS")

cat("✅ 프롬프트 생성 완료\n")
cat("💾 'data/prompts_ready.RDS' 저장 완료\n")
cat("➡️ 다음: 02_single_analysis_test.R 실행\n")