# 🔄 재분석 관리 시스템 완전 가이드

## 🎯 개요

**재분석 관리 시스템**은 **샘플링 테스트의 결과가 좋지 않거나 프롬프트 개선으로 인해 이전 분석들을 다시 분석해야 하는 상황**을 완벽하게 지원하는 고급 시스템입니다.

---

## 🌟 핵심 기능

### 1. **분석 품질 자동 평가**
- 감정 분석 결과의 품질을 자동으로 측정 (0-1 점수)
- 오류율, 유효 결과율, 감정 다양성, 파싱 성공률 종합 평가
- 품질 임계값 기반 재분석 필요성 자동 판단

### 2. **프롬프트 버전 관리**
- 프롬프트 함수의 변경사항을 자동 감지 (해시 기반)
- 프롬프트 버전별 성능 지표 추적
- 프롬프트 개선 이력 및 효과 측정

### 3. **선택적 이력 무효화**
- 품질이 낮은 분석 결과만 선별적으로 삭제
- 날짜, 모델, 분석 유형, 품질 점수별 무효화
- 안전한 백업 시스템으로 실수 방지

### 4. **스마트 재분석 계획**
- 우선순위 기반 재분석 대상 선별
- 배치 처리 계획 및 비용/시간 예측
- 체크포인트 기반 실패 복구 지원

---

## 🚀 주요 사용 시나리오

### 시나리오 1: 샘플 테스트 품질 문제

```r
# 재분석 관리자 초기화
reanalysis_mgr <- ReanalysisManager$new()

# 샘플 테스트 결과 품질 평가
sample_results <- readRDS("results/analysis_results_SAMPLE_100.RDS")
quality_eval <- reanalysis_mgr$evaluate_analysis_quality(sample_results)

print(paste("품질 점수:", round(quality_eval$quality_score, 2)))
print("문제점:")
print(quality_eval$issues)

# 재분석 필요 판단
if (quality_eval$needs_reanalysis) {
  cat("🔄 재분석이 필요합니다!")
}
```

**품질 평가 기준:**
- ✅ 품질 점수 0.6 이상: 양호
- ⚠️ 품질 점수 0.4-0.6: 주의 (선택적 재분석)
- 🚨 품질 점수 0.4 미만: 재분석 필수

### 시나리오 2: 프롬프트 개선 후 재분석

```r
# 1단계: 개선된 프롬프트 버전 등록
new_version_id <- reanalysis_mgr$register_prompt_version(
  analyze_emotion_improved,  # 개선된 분석 함수
  description = "오류율 감소 및 감정 구분력 향상",
  performance_data = list(expected_improvement = "오류율 50% 감소")
)

# 2단계: 기존 저품질 분석 이력 무효화
reanalysis_mgr$invalidate_analysis_history(
  invalidation_criteria = list(
    quality_threshold = 0.5,  # 품질 점수 0.5 미만만
    analysis_types = c("sample", "test"),
    date_range = c(Sys.time() - 7*24*60*60, Sys.time())  # 최근 1주일
  ),
  reason = "프롬프트 개선으로 인한 재분석"
)

# 3단계: 재분석 대상 식별
candidates <- reanalysis_mgr$identify_reanalysis_candidates(
  criteria = list(
    older_than_days = 7,
    error_types = c("API 오류", "파싱 오류")
  )
)

# 4단계: 재분석 실행
reanalysis_plan <- reanalysis_mgr$create_reanalysis_plan(
  target_data = candidates,
  reason = "프롬프트 개선",
  priority_scoring = TRUE
)

print(sprintf("재분석 대상: %d건, 예상 시간: %.1f분", 
              reanalysis_plan$total_items,
              reanalysis_plan$total_estimated_time_mins))
```

### 시나리오 3: 자동 품질 모니터링

```r
# 시스템 전체 재분석 권장사항 확인
recommendations <- reanalysis_mgr$recommend_reanalysis(
  recent_results = latest_analysis_results,
  auto_check_history = TRUE
)

# 권장사항 출력
for (rec_type in names(recommendations)) {
  rec <- recommendations[[rec_type]]
  cat(sprintf("[%s] %s - 영향: %d건\n", 
              rec$priority, rec$reason, rec$affected_count))
}
```

---

## 📊 품질 평가 상세

### 품질 지표 구성

| 지표 | 가중치 | 설명 |
|------|--------|------|
| **유효 결과율** | 40% | 오류가 아닌 실제 감정 분석 결과 비율 |
| **오류율 (반전)** | 30% | API/파싱/분석 오류 발생률의 역수 |
| **감정 다양성** | 20% | 8개 기본 감정 중 탐지된 감정 종류 수 |
| **파싱 성공률** | 10% | JSON 파싱 성공률 |

### 품질 문제 자동 탐지

```r
# 자동으로 탐지되는 문제들:
problems_detected <- list(
  high_error_rate = "오류율 10% 초과",
  low_valid_rate = "유효 결과 70% 미만", 
  excessive_neutral = "중립 감정 70% 초과 (구분력 부족)",
  low_diversity = "감정 다양성 5종류 미만",
  parsing_failures = "파싱 실패율 5% 초과"
)
```

---

## 🔧 고급 설정

### 품질 임계값 커스터마이징

```r
# 사용자 정의 품질 기준 설정
custom_thresholds <- list(
  min_valid_emotions = 0.8,    # 유효 감정 80% 이상
  max_error_rate = 0.05,       # 오류율 5% 이하
  min_confidence_score = 0.7,  # 최소 신뢰도 0.7
  max_parsing_errors = 0.03    # 파싱 오류 3% 이하
)

# 재분석 관리자에 적용
reanalysis_mgr$quality_thresholds <- custom_thresholds
```

### 재분석 우선순위 규칙

```r
# 우선순위 점수 계산 로직
priority_rules <- list(
  api_errors = 10,        # API 오류 최우선
  parsing_errors = 8,     # 파싱 오류
  analysis_errors = 7,    # 분석 오류  
  na_results = 9,         # NA 결과
  neutral_heavy = 6,      # 중립 과다
  normal_results = 5      # 일반 결과
)
```

---

## 💡 실전 활용 팁

### 1. **단계별 품질 개선 접근**

```r
# Step 1: 현재 상태 진단
quality_assessment <- reanalysis_mgr$evaluate_analysis_quality(current_results)

# Step 2: 문제 유형별 대응
if ("높은 오류율" %in% quality_assessment$issues) {
  # → API 안정성 개선, 재시도 로직 강화
} 
if ("과도한 중립 감정" %in% quality_assessment$issues) {
  # → 프롬프트 명확성 향상, 감정 구분 기준 세분화
}

# Step 3: 점진적 개선 및 검증
# → A/B 테스트로 개선 효과 측정
```

### 2. **프롬프트 버전 실험**

```r
# 여러 프롬프트 버전을 체계적으로 비교
versions_to_test <- list(
  "conservative" = analyze_emotion_conservative,  # 보수적 판단
  "detailed" = analyze_emotion_detailed,         # 상세한 분석
  "fast" = analyze_emotion_fast                  # 빠른 처리
)

# 각 버전별 품질 측정 후 최적 버전 선택
```

### 3. **배치 처리 최적화**

```r
# 재분석 배치 크기 조정
optimal_batch_size <- min(
  API_CONFIG$rate_limit_per_minute,  # API 제한 고려
  available_memory / expected_memory_per_item,  # 메모리 고려
  50  # 기본 최대값
)
```

---

## 📈 성능 모니터링

### 품질 개선 추적

```r
# 시간별 품질 변화 추적
quality_trend <- track_quality_over_time(
  start_date = Sys.time() - 30*24*60*60,  # 최근 30일
  interval = "daily"
)

# 모델별 성능 비교
model_comparison <- compare_model_performance(
  models = c("gemini-2.5-flash", "gpt-4", "claude-3"),
  metric = "quality_score"
)
```

### 비용 효과 분석

```r
# 재분석으로 인한 품질 개선 vs 비용
roi_analysis <- calculate_reanalysis_roi(
  quality_improvement = 0.25,  # 품질 0.25점 향상
  reanalysis_cost = 50,        # $50 재분석 비용
  business_value_per_quality = 200  # 품질 1점당 비즈니스 가치 $200
)

# ROI = (0.25 * 200 - 50) / 50 = 0.2 (20% 수익률)
```

---

## 🔍 문제 해결

### 자주 발생하는 문제들

#### 1. **무효화된 이력 복구**
```r
# 실수로 무효화한 경우 백업에서 복구
backup_files <- list.files("analysis_history/", pattern = "backup_.*\\.RDS")
latest_backup <- tail(sort(backup_files), 1)
restored_history <- readRDS(file.path("analysis_history", latest_backup))
```

#### 2. **재분석 중단 복구**
```r
# 체크포인트에서 재개
checkpoint_mgr <- CheckpointManager$new()
last_checkpoint <- checkpoint_mgr$load_checkpoint("reanalysis_batch_3")
# 3번 배치부터 재시작
```

#### 3. **품질 점수 이상값**
```r
# 품질 평가 로직 검증
debug_quality_evaluation(suspicious_results)
```

---

## 📚 API 레퍼런스

### ReanalysisManager 주요 메서드

| 메서드 | 설명 | 반환값 |
|--------|------|--------|
| `evaluate_analysis_quality()` | 분석 품질 평가 | 품질 점수, 문제점, 재분석 필요성 |
| `register_prompt_version()` | 프롬프트 버전 등록 | 버전 ID |
| `invalidate_analysis_history()` | 선택적 이력 무효화 | 남은 이력 |
| `identify_reanalysis_candidates()` | 재분석 대상 식별 | 후보 데이터프레임 |
| `create_reanalysis_plan()` | 재분석 계획 수립 | 배치 계획 및 비용 추정 |
| `recommend_reanalysis()` | 자동 재분석 권장 | 권장사항 리스트 |

---

## 🎉 결론

이 재분석 관리 시스템으로 다음이 가능해집니다:

✅ **자동 품질 모니터링**: 분석 품질을 지속적으로 감시  
✅ **스마트 재분석**: 필요한 경우에만 선별적으로 재분석  
✅ **프롬프트 최적화**: 체계적인 프롬프트 개선 및 효과 측정  
✅ **비용 효율성**: 불필요한 재분석 방지로 API 비용 절약  
✅ **품질 보장**: 일관되게 높은 품질의 분석 결과 유지  

**이제 프롬프트 개선이나 품질 문제로 인한 재분석 상황을 완벽하게 처리할 수 있습니다!** 🚀