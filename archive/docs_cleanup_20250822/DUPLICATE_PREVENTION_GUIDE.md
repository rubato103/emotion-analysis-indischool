# 🔄 중복 분석 방지 시스템 가이드

## 🎯 개요

중복 분석 방지 시스템은 **샘플링 테스트나 이전 분석에서 이미 처리된 데이터를 자동으로 식별하고 제외**하여, API 호출 비용과 분석 시간을 크게 절약하는 시스템입니다.

---

## 💡 핵심 아이디어

```
문제점: 
- 샘플 테스트로 100건 분석 → 전체 분석 시 동일한 100건을 또 분석
- API 비용 중복, 시간 낭비

해결책:
- 분석 이력 자동 추적
- 전체 분석 시 기분석 데이터 자동 제외
- 새로운 데이터만 분석하여 비용/시간 절약
```

---

## 🔧 주요 기능

### 1. **분석 이력 자동 추적**
- 모든 분석 결과를 자동으로 기록
- 분석 일시, 모델, 결과 등 메타데이터 저장
- 고유 ID 기반 중복 식별

### 2. **스마트 필터링**
- 분석 유형별 제외 (sample, test, full)
- 모델별 제외 (같은 모델로 분석한 것만)
- 시간 기반 제외 (최근 N일간만 고려)

### 3. **비용 절약 계산**
- 제외된 API 호출 수 자동 계산
- 예상 절약 비용 표시
- 시간 절약 효과 측정

---

## 🚀 사용 시나리오

### 시나리오 1: 샘플 테스트 → 전체 분석
```r
# 1단계: 샘플 테스트 (100건)
source("02_단건분석_테스트_v2.R")  # 100건 분석, 이력 저장

# 2단계: 전체 분석 (10,000건)
source("03_감정분석_전체실행_v2.R")  # 9,900건만 새로 분석
```

**효과:**
- API 호출: 10,000건 → 9,900건 (100건 절약)
- 시간 절약: 약 2.5분 (100건 × 1.5초)
- 비용 절약: 약 $0.10 (API 호출당 $0.001 가정)

### 시나리오 2: 점진적 분석
```r
# 1일차: 일부 분석
ANALYSIS_CONFIG$sample_post_count <- 50
source("03_감정분석_전체실행_v2.R")  # 50개 게시글 분석

# 2일차: 추가 분석
ANALYSIS_CONFIG$sample_post_count <- 100  
source("03_감정분석_전체실행_v2.R")  # 50개만 새로 분석

# 3일차: 전체 분석
ANALYSIS_CONFIG$sample_post_count <- 0
source("03_감정분석_전체실행_v2.R")  # 기분석 100개 제외하고 나머지만
```

### 시나리오 3: 모델 변경 테스트
```r
# GPT-4로 샘플 테스트
TEST_CONFIG$model_name <- "gpt-4"
source("02_단건분석_테스트_v2.R")

# Gemini로 전체 분석 (GPT-4 결과는 제외하지 않음)
API_CONFIG$model_name <- "gemini-2.5-flash"
source("03_감정분석_전체실행_v2.R")  # 모든 데이터 분석 (모델이 다르므로)
```

---

## 📊 분석 이력 관리

### 이력 확인
```r
# 분석 이력 관리자 생성
tracker <- AnalysisTracker$new()

# 전체 통계 확인
stats <- tracker$get_analysis_stats()
print(stats)
```

**출력 예시:**
```
$total
[1] 1250

$by_type
  analysis_type count latest_analysis        
1 test          15    2024-01-15 14:30:22
2 sample        185   2024-01-15 15:45:13  
3 full          1050  2024-01-15 16:20:35

$by_model
  model_used                      count latest_analysis
1 gemini-2.5-flash-lite-preview   1200  2024-01-15 16:20:35
2 gpt-4                          50    2024-01-14 10:15:22
```

### 특정 조건으로 필터링
```r
# 최근 7일간 테스트 분석만
analyzed_ids <- tracker$get_analyzed_ids(
  analysis_type = "test",
  days_back = 7
)

# 특정 모델로 분석한 것만
analyzed_ids <- tracker$get_analyzed_ids(
  model_filter = "gemini-2.5-flash-lite-preview",
  days_back = 30
)
```

### 수동 제외 설정
```r
# 미분석 데이터만 추출
unanalyzed_data <- tracker$filter_unanalyzed(
  data = full_dataset,
  exclude_types = c("sample", "test"),  # 샘플과 테스트 제외
  model_filter = "gemini-2.5-flash",   # 특정 모델만 제외
  days_back = 14  # 최근 2주간만 고려
)
```

---

## ⚙️ 설정 옵션

### 기본 설정 (config.R)
```r
DUPLICATE_PREVENTION_CONFIG <- list(
  enable_tracking = TRUE,           # 이력 추적 사용 여부
  auto_exclude_duplicates = TRUE,   # 자동 중복 제외 여부
  default_exclude_types = c("sample", "test"),  # 기본 제외 유형
  default_days_back = 30,           # 기본 고려 기간
  history_cleanup_days = 90         # 이력 정리 주기
)
```

### 스크립트별 사용자 정의
```r
# 전체 분석에서만 중복 제외
if (script_type == "full_analysis") {
  exclude_types <- c("sample", "test", "full")
} else {
  exclude_types <- c("test")  # 테스트는 테스트끼리만 제외
}
```

---

## 📂 파일 구조

```
analysis_history/
├── analysis_history.RDS              # 메인 이력 파일
├── backup_2024-01-15.RDS            # 백업 파일 (자동 생성)
└── cleanup_log.txt                   # 정리 로그

results/
├── analysis_results_SAMPLE_100.RDS   # 샘플 분석 결과
├── analysis_results_FULL.RDS         # 전체 분석 결과
└── merged_results_final.RDS          # 병합된 최종 결과
```

---

## 🔍 고급 기능

### 1. 스마트 병합
```r
# 기분석 결과와 신규 분석 결과 자동 병합
merged_results <- merge_analysis_results(
  previous_files = c("results/analysis_results_SAMPLE_100.RDS"),
  new_results = current_analysis_results,
  conflict_resolution = "keep_latest"  # 충돌 시 최신 결과 유지
)
```

### 2. 분석 품질 검증
```r
# 중복 제거 전후 비교
comparison <- compare_analysis_quality(
  original_plan = "10000건 전체 분석",
  optimized_plan = "9900건 (100건 중복 제외)"
)
```

### 3. 배치 최적화
```r
# 미분석 데이터를 배치로 나누어 효율적 처리
optimized_batches <- create_optimized_batches(
  unanalyzed_data = filtered_data,
  batch_size = 50,
  priority_scoring = TRUE  # 우선순위 기반 정렬
)
```

---

## ⚠️ 주의사항

### 1. **데이터 일관성**
- 원본 데이터가 변경되면 기존 이력이 무효화될 수 있음
- 중요한 변경사항이 있을 때는 이력 초기화 고려

### 2. **모델 호환성**
- 다른 모델로 분석한 결과는 자동으로 제외되지 않음
- 모델별 비교가 필요한 경우 명시적으로 설정

### 3. **저장 공간**
- 분석 이력이 누적되면 상당한 용량 차지
- 정기적인 정리 또는 압축 필요

---

## 🛠️ 문제 해결

### 이력 파일 손상
```r
# 이력 파일 재생성
file.remove("analysis_history/analysis_history.RDS")
tracker <- AnalysisTracker$new()  # 새로 초기화
```

### 과도한 제외
```r
# 강제 전체 분석 (이력 무시)
unanalyzed_data <- full_dataset  # 필터링 없이 전체 사용
```

### 이력 수동 편집
```r
# 특정 분석 결과 제거
history <- tracker$load_history()
cleaned_history <- history %>% 
  filter(!(analysis_type == "test" & analysis_date < "2024-01-01"))
saveRDS(cleaned_history, tracker$history_file)
```

---

## 💰 예상 절약 효과

| 상황 | 전체 데이터 | 샘플 테스트 | 중복 제외 | 절약 효과 |
|------|-------------|-------------|-----------|-----------|
| **소규모** | 1,000건 | 100건 | 100건 (10%) | 시간: 2.5분<br>비용: $0.10 |
| **중규모** | 10,000건 | 500건 | 500건 (5%) | 시간: 12.5분<br>비용: $0.50 |
| **대규모** | 100,000건 | 1,000건 | 1,000건 (1%) | 시간: 25분<br>비용: $1.00 |

**실제 프로젝트에서는 더 큰 절약 효과를 기대할 수 있습니다:**
- 여러 번의 테스트와 점진적 분석
- 실패 후 재시작 시 중복 방지
- 모델 비교 실험 시 기존 결과 활용

이 시스템으로 **효율적이고 경제적인 대용량 감정분석**이 가능해집니다!