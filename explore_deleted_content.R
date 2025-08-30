# 삭제된 게시물/댓글 탐색 스크립트
# 목적: 데이터 컬렉션에서 삭제된 콘텐츠의 패턴을 분석

# 필요한 라이브러리 로드
library(arrow)
library(dplyr)
library(stringr)

# 1. 원본 데이터 로드
cat("=== 원본 데이터 로드 ===\n")
if (file.exists("data/data_collection.csv")) {
  # CSV 파일 로드
  corpus_df <- read.csv("data/data_collection.csv", stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  cat("✅ 원본 데이터 로드 성공:", nrow(corpus_df), "행,", ncol(corpus_df), "열\n")
  
  # 기본 구조 확인
  cat("\n열 이름:\n")
  print(names(corpus_df))
  
  cat("\n데이터 샘플:\n")
  print(head(corpus_df))
  
  # '구분' 컬럼 확인
  if ("구분" %in% names(corpus_df)) {
    cat("\n구분별 데이터 수:\n")
    print(table(corpus_df$구분, useNA = "always"))
  }
  
  # 'content' 컬럼 확인
  if ("content" %in% names(corpus_df)) {
    cat("\ncontent 컬럼의 NA 값 수:", sum(is.na(corpus_df$content)), "\n")
    
    # 삭제 관련 텍스트 패턴 탐색
    cat("\n=== 삭제 관련 패턴 탐색 ===\n")
    
    # 삭제 메시지 패턴
    deletion_patterns <- c(
      "삭제된",
      "삭제 되",
      "삭제하였습니다",
      "삭제됨",
      "삭제된 댓글",
      "삭제된 게시글",
      "작성자가.*삭제",
      "삭제.*작성자",
      "비밀 댓글",
      "내용 없음",
      "삭제되어",
      "삭제 돼",
      "삭제 됨"
    )
    
    # 각 패턴에 대한 검색
    for (pattern in deletion_patterns) {
      matches <- corpus_df %>%
        filter(!is.na(content)) %>%
        filter(str_detect(content, pattern))
      
      if (nrow(matches) > 0) {
        cat(sprintf("'%s' 패턴 매칭: %d건\n", pattern, nrow(matches)))
        if (nrow(matches) <= 10) {
          cat("  샘플:\n")
          for (i in 1:min(5, nrow(matches))) {
            cat(sprintf("    %d. %s\n", i, substr(matches$content[i], 1, 100)))
          }
        }
      }
    }
    
    # 'content' 컬럼의 고유한 값들 확인 (상위 20개)
    cat("\n=== content 컬럼의 상위 20개 고유값 ===\n")
    unique_contents <- corpus_df %>%
      filter(!is.na(content)) %>%
      count(content, sort = TRUE) %>%
      head(20)
    print(unique_contents)
    
    # 빈 문자열 또는 공백만 있는 내용 확인
    cat("\n=== 빈 내용 또는 공백만 있는 항목 ===\n")
    empty_contents <- corpus_df %>%
      filter(is.na(content) | content == "" | str_trim(content) == "")
    cat("빈 내용 항목 수:", nrow(empty_contents), "\n")
    
    # '삭제' 단어가 포함된 내용 분석
    cat("\n=== '삭제' 단어가 포함된 내용 분석 ===\n")
    deleted_contents <- corpus_df %>%
      filter(!is.na(content)) %>%
      filter(str_detect(content, "삭제"))
    
    cat("삭제 관련 내용 수:", nrow(deleted_contents), "\n")
    
    if (nrow(deleted_contents) > 0) {
      # 삭제 내용의 상위 10개 패턴
      cat("\n상위 10개 삭제 메시지 패턴:\n")
      deletion_patterns_top <- deleted_contents %>%
        count(content, sort = TRUE) %>%
        head(10)
      print(deletion_patterns_top)
      
      # '구분'별 삭제 내용 수
      if ("구분" %in% names(deleted_contents)) {
        cat("\n구분별 삭제 내용 수:\n")
        print(table(deleted_contents$구분, useNA = "always"))
      }
    }
  }
  
  # depth 컬럼 분석 (댓글 구조)
  if ("depth" %in% names(corpus_df)) {
    cat("\n=== depth 컬럼 분석 ===\n")
    cat("depth 값 분포:\n")
    print(table(corpus_df$depth, useNA = "always"))
  }
  
  # author 컬럼 분석 (탈퇴 회원 관련)
  if ("author" %in% names(corpus_df)) {
    cat("\n=== author 컬럼 분석 ===\n")
    withdrawal_patterns <- c("탈퇴", "탈퇴회원", "삭제된.*계정", "알수없는.*사용자")
    
    for (pattern in withdrawal_patterns) {
      matches <- corpus_df %>%
        filter(!is.na(author)) %>%
        filter(str_detect(author, pattern))
      
      if (nrow(matches) > 0) {
        cat(sprintf("'%s' 패턴 매칭 (author): %d건\n", pattern, nrow(matches)))
        if (nrow(matches) <= 5) {
          cat("  샘플:\n")
          for (i in 1:nrow(matches)) {
            cat(sprintf("    %d. %s\n", i, matches$author[i]))
          }
        }
      }
    }
  }
  
  # prompts_ready.parquet 파일이 있는지 확인
  cat("\n=== prompts_ready 파일 확인 ===\n")
  prompts_files <- c("data/prompts_ready.parquet", "data/prompts_ready.RDS")
  for (file in prompts_files) {
    if (file.exists(file)) {
      cat("✅", file, "파일 존재\n")
      if (grepl("\\.parquet$", file)) {
        prompts_df <- arrow::read_parquet(file)
        cat("   행 수:", nrow(prompts_df), ", 열 수:", ncol(prompts_df), "\n")
      } else {
        prompts_df <- readRDS(file)
        cat("   행 수:", nrow(prompts_df), ", 열 수:", ncol(prompts_df), "\n")
      }
    } else {
      cat("❌", file, "파일 없음\n")
    }
  }
  
} else {
  cat("❌ 원본 데이터 파일을 찾을 수 없습니다: data/data_collection.csv\n")
}

cat("\n=== 탐색 완료 ===\n")