# 📋 실패 복구 시스템 사용 가이드

## 🎯 개요

실패 복구 시스템은 분석 파이프라인 중 실패가 발생했을 때, 처음부터 다시 시작하지 않고 실패한 지점에서 재시작할 수 있게 해주는 시스템입니다.

## 🔧 주요 기능

### 1. **체크포인트 시스템**
- 각 단계별로 중간 결과를 자동 저장
- 실패 시 가장 최근 체크포인트에서 재시작
- 체크포인트 유효성 검증 (시간, 데이터 품질)

### 2. **배치 처리 복구**
- 대용량 데이터를 작은 배치로 나누어 처리
- 배치별 진행상황 추적
- 실패한 배치만 재처리

### 3. **자동 정리**
- 오래된 체크포인트 자동 삭제
- 저장 공간 효율적 관리

---

## 🚀 사용 방법

### 기본 복구 적용

```r
# 단일 함수에 복구 시스템 적용
result <- with_recovery("step_name", "script_name", function() {
  # 실제 작업 수행
  expensive_operation()
})
```

### 배치 처리 복구 적용

```r
# 대량 데이터 처리에 배치 복구 적용
result <- process_with_batch_recovery(
  data = large_dataset,
  process_function = function(batch) {
    # 배치별 처리 로직
    return(processed_batch)
  },
  batch_size = 100,
  checkpoint_name = "batch_processing",
  script_name = "my_script"
)
```

---

## 📝 실제 사용 시나리오

### 시나리오 1: 전체 감정분석 중 네트워크 오류
```
상황: 1000건 중 700건 처리 후 API 연결 실패
해결: 700건까지의 결과는 체크포인트에 저장됨
     → 재시작 시 701건부터 자동 재개
```

### 시나리오 2: 데이터 전처리 중 메모리 부족
```
상황: 대용량 데이터 처리 중 메모리 부족으로 중단
해결: 배치별로 처리하여 완료된 배치는 저장됨
     → 실패한 배치부터 재시작
```

### 시나리오 3: 구글 시트 업로드 중 인증 만료
```
상황: 분석 완료 후 구글 시트 업로드 중 인증 문제
해결: 분석 결과는 이미 체크포인트에 저장됨
     → 인증 재설정 후 업로드 단계만 재실행
```

---

## 📂 파일 구조

```
checkpoints/
├── 01_data_loading_load_data_2024-01-15.RDS        # 데이터 로드 체크포인트
├── 01_data_loading_extract_posts_2024-01-15.RDS    # 게시글 추출 체크포인트
├── 01_data_loading_prompt_generation_progress.RDS   # 배치 진행상황
└── 03_analysis_api_processing_batch_1.RDS          # API 처리 배치별 저장
```

---

## ⚙️ 설정 옵션 (config.R)

```r
RECOVERY_CONFIG <- list(
  enable_checkpoints = TRUE,              # 체크포인트 사용 여부
  checkpoint_dir = "checkpoints",         # 체크포인트 저장 디렉토리
  max_checkpoint_age_hours = 24,          # 체크포인트 최대 유효 시간
  cleanup_days = 7,                       # 자동 정리 주기 (일)
  batch_size = 100,                       # 기본 배치 크기
  auto_recover = TRUE                     # 자동 복구 시도 여부
)
```

---

## 🔍 체크포인트 관리

### 체크포인트 확인
```r
# 체크포인트 관리자 생성
cm <- CheckpointManager$new("script_name")

# 저장된 체크포인트 목록 확인
checkpoints <- cm$list_checkpoints()
print(checkpoints)
```

### 수동 체크포인트 저장
```r
# 중요한 중간 결과를 수동으로 체크포인트 저장
cm$save_checkpoint(important_data, "critical_step")
```

### 특정 체크포인트 로드
```r
# 특정 단계의 체크포인트 수동 로드
data <- cm$load_checkpoint("step_name")
```

### 오래된 체크포인트 정리
```r
# 7일 이상 된 체크포인트 삭제
cm$cleanup_old_checkpoints(keep_days = 7)
```

---

## 🚨 주의사항

### 1. **저장 공간**
- 체크포인트는 상당한 저장 공간을 사용할 수 있음
- 정기적인 정리 필요 (자동 정리 기능 활용)

### 2. **데이터 일관성**
- 체크포인트 생성 후 원본 데이터가 변경되면 무효화됨
- 데이터 변경 시 `force_rerun = TRUE` 옵션 사용

### 3. **버전 호환성**
- R 버전이나 패키지 버전이 크게 달라지면 체크포인트가 작동하지 않을 수 있음
- 세션 정보도 함께 저장되므로 호환성 확인 가능

---

## 🛠️ 문제 해결

### 체크포인트 로드 실패
```r
# 강제 재시작
result <- with_recovery("step_name", "script_name", 
                       recovery_function, force_rerun = TRUE)
```

### 배치 처리 중단
```r
# 진행상황 파일 확인
progress_file <- "checkpoints/script_batch_processing_progress.RDS"
if (file.exists(progress_file)) {
  progress <- readRDS(progress_file)
  cat("완료된 배치:", length(progress$completed_batches))
}
```

### 체크포인트 디렉토리 초기화
```r
# 모든 체크포인트 삭제 후 처음부터 시작
unlink("checkpoints", recursive = TRUE)
```

---

## 💡 모범 사례

1. **적절한 체크포인트 지점**
   - 시간이 오래 걸리는 작업 전후
   - 네트워크 통신이 필요한 작업 전후
   - 데이터 변환의 주요 단계

2. **배치 크기 조정**
   - API 호출: 50-100개 (호출 제한 고려)
   - 데이터 처리: 1000-5000개 (메모리 고려)
   - 파일 저장: 10000개 (I/O 효율성)

3. **정기적인 정리**
   - 주요 분석 완료 후 불필요한 체크포인트 정리
   - 저장 공간 모니터링

이 시스템을 통해 대용량 데이터 분석 시에도 안정적이고 효율적인 파이프라인 운영이 가능합니다.