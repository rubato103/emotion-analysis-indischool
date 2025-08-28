# 데이터 불러오기 및 프롬프트 생성
# 목적: CSV 데이터를 불러오고 API 요청용 프롬프트 생성, Parquet 저장

# 통합 초기화 시스템 로드 (Parquet 전용)
source("libs/init.R")
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
  # 숫자 컬럼 변환 및 comment_id 처리
  corpus_df <- corpus_df %>%
    mutate(across(c(post_id, comment_id, depth, views, likes), as.numeric)) %>%
    mutate(comment_id = if_else(구분 == "게시글" & is.na(comment_id), 0, comment_id))
  cat("✅ 데이터 로드 및 전처리 완료\n")
} else {
  stop("⚠️ 'data/data_collection.csv' 파일을 찾을 수 없습니다.")
}

# 3. 프롬프트 생성 (depth를 고려한 동적 구성 - 최적화 버전)
log_message("INFO", "프롬프트 생성을 시작합니다...")

# 게시글 제목/내용 추출
log_message("INFO", "(1/5) 원본 게시글 정보 추출 중...")
posts_lookup <- corpus_df %>%
  filter(구분 == "게시글") %>%
  select(post_id, post_title = title, post_context = content)

# 데이터 정렬 및 부모 댓글 찾기 (벡터화 방식)
log_message("INFO", "(2/5) 데이터 정렬 및 게시글 정보 결합 중...")
corpus_with_context <- corpus_df %>%
  # post_id와 comment_id로 정렬 (순서 보장)
  arrange(post_id, comment_id) %>%
  # 게시글 정보 결합
  left_join(posts_lookup, by = "post_id")

log_message("INFO", "(3/5) 부모 댓글의 맥락을 구성하는 중... (데이터가 많을 시 수십 초 소요)")
corpus_with_parent_info <- corpus_with_context %>%
  # 각 depth별 최근 content를 기록할 컬럼 생성
  mutate(
    content_d0 = if_else(depth == 0, content, NA_character_),
    content_d1 = if_else(depth == 1, content, NA_character_),
    content_d2 = if_else(depth == 2, content, NA_character_),
    content_d3 = if_else(depth == 3, content, NA_character_)
  ) %>%
  # post_id 그룹 내에서 아래로 값 채우기
  group_by(post_id) %>%
  tidyr::fill(content_d0, content_d1, content_d2, content_d3, .direction = "down") %>%
  ungroup() %>%
  # 부모 댓글 내용 찾기
  mutate(
    parent_comment = case_when(
      depth == 1 ~ content_d0,
      depth == 2 ~ content_d1,
      depth == 3 ~ content_d2,
      depth == 4 ~ content_d3,
      TRUE ~ NA_character_
    )
  )

log_message("INFO", "(4/5) 전체 프롬프트를 최종 생성하는 중...")
corpus_with_prompts <- corpus_with_parent_info %>%
  # 프롬프트 생성
  mutate(
    prompt = pmap_chr(
      list(
        text = content,
        구분 = 구분,
        title = title,
        context = post_context,
        context_title = post_title,
        parent_comment = parent_comment,
        batch_mode = TRUE  # 항상 배치 모드 기준 프롬프트 생성
      ),
      create_analysis_prompt
    )
  ) %>%
  # 불필요한 컬럼 제거
  select(-starts_with("content_d"), -post_context, -post_title, -parent_comment)

log_message("INFO", "(5/5) 프롬프트 생성 완료")



# 4. RDS 저장
save_parquet(corpus_with_prompts, "data/prompts_ready")

cat("✅ 프롬프트 생성 완료\n")
cat("💾 'data/prompts_ready.parquet' 저장 완료\n")
cat("➡️ 다음: 02_single_analysis_test.R 실행\n")