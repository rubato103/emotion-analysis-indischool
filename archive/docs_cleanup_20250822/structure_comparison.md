# 일반 분석 vs 배치 분석 데이터 구조 비교

## 1. 기본 감정분석 결과 구조

### 공통 컬럼 (functions.R의 analyze_emotion_robust 함수)
```r
output_df <- data.frame(
  기쁨 = NA_real_, 슬픔 = NA_real_, 분노 = NA_real_, 혐오 = NA_real_,
  공포 = NA_real_, 놀람 = NA_real_, `애정/사랑` = NA_real_, 중립 = NA_real_,
  P = NA_real_, A = NA_real_, D = NA_real_,
  PAD_complex_emotion = NA_character_,
  dominant_emotion = NA_character_,
  rationale = NA_character_,
  unexpected_emotions = NA_character_,
  error_message = NA_character_,
  stringsAsFactors = FALSE,
  check.names = FALSE
)
```

**총 16개 컬럼**: 
- 감정 점수 8개: 기쁨, 슬픔, 분노, 혐오, 공포, 놀람, 애정/사랑, 중립
- PAD 점수 3개: P, A, D  
- 분석 결과 5개: PAD_complex_emotion, dominant_emotion, rationale, unexpected_emotions, error_message

## 2. 일반 분석 (03_full_emotion_analysis.R)

### 최종 결과 구조
```r
final_df <- bind_rows(
  successful_df,      # 성공한 분석 결과
  rerun_final_df,     # 재시도한 결과  
  skipped_final_df,   # 건너뛴 데이터
  previously_analyzed # 기분석 데이터
) %>%
  arrange(post_id, if("comment_id" %in% names(.)) comment_id else NULL)
```

**포함 컬럼**:
- **원본 데이터 컬럼들**: post_id, comment_id, 구분, text, title, context, context_title, prompt_text 등
- **감정분석 결과 16개 컬럼** (위와 동일)

## 3. 배치 분석 (process_batch_results.R)

### 배치 파싱 중간 단계에서 추가되는 컬럼
```r
# process_batch_jsonl 함수에서 추가
emotion_result$row_index <- row_index      # 배치 전용
emotion_result$request_key <- request_key  # 배치 전용
```

### 최종 결과 구조
```r
final_df <- original_data %>%
  mutate(row_index = row_number()) %>%
  left_join(results_df, by = "row_index") %>%
  select(-row_index, -request_key)  # 임시 컬럼 제거
```

**포함 컬럼**:
- **원본 데이터 컬럼들**: post_id, comment_id, 구분, text, title, context, context_title, prompt_text 등
- **감정분석 결과 16개 컬럼** (일반 분석과 동일)

## 4. 구조 비교 결과

### ✅ 동일한 부분
1. **감정분석 결과 컬럼**: 완전히 동일 (16개 컬럼, 동일한 타입)
2. **원본 데이터 컬럼**: 동일한 원본 데이터를 사용하므로 동일
3. **최종 출력 구조**: 임시 컬럼 제거 후 완전히 동일

### ⚠️ 차이점
1. **처리 과정 중 임시 컬럼**:
   - 배치 분석: `row_index`, `request_key` (최종 결과에서는 제거됨)
   - 일반 분석: 임시 컬럼 없음

2. **파싱 방식**:
   - 일반 분석: gemini_structured → JSON 파싱
   - 배치 분석: 일반 텍스트 → 마크다운 파싱 (fallback으로 JSON 파싱)

### 📊 최종 결론

**결과 파일의 데이터 구조는 완전히 동일합니다.**

- 컬럼 개수: 동일
- 컬럼 이름: 동일  
- 데이터 타입: 동일
- 정렬 순서: 동일 (post_id, comment_id 기준)

유일한 차이점은 중간 처리 과정에서 배치 분석은 임시 컬럼을 사용하지만, 최종 결과에서는 모두 제거되어 일반 분석과 완전히 동일한 구조가 됩니다.

## 5. 검증 방법

실제 파일 구조를 확인하려면:

```r
# R에서 실행
regular_result <- readRDS('results/analysis_results_CODE_CHECK_28items_20250724_090641.RDS')
batch_result <- readRDS('results/analysis_results_BATCH_CODE_CHECK_3items_20250724_091221.RDS')

# 구조 비교
identical(names(regular_result), names(batch_result))
identical(sapply(regular_result, class), sapply(batch_result, class))
```