# 배치 처리 완전 가이드 (개선됨)

배치 처리 시스템이 개선되어 완전 자동화된 워크플로우를 제공합니다.

## 🔄 개선된 배치 처리 워크플로우

### **통합 원스톱 처리** (추천)
```r
source("batch_utils.R")
result <- run_batch_with_monitoring("sampling")  # 제출→모니터링→결과처리
```

### **단계별 처리**
1. **제출**: `04_batch_emotion_analysis.R`
2. **모니터링**: `06_batch_monitor.R`  
3. **결과처리**: 자동 다운로드 및 파싱

## 📊 배치 처리 모드 분류

### **테스트용 배치 모드**
#### `code_check` (1개 게시물)
- **용도**: 프롬프트 및 코드 검증
- **처리시간**: 24시간 내 (보통 1-2시간)
- **비용**: 50% 할인

#### `pilot` (5개 게시물)  
- **용도**: 예비 분석 및 방법론 검증
- **처리시간**: 24시간 내 (보통 2-4시간)
- **비용**: 50% 할인

### **전수분석용 배치 모드** ⚠️ 신뢰도 분석 불필요
#### `sampling` (384+ 샘플)
- **용도**: 통계적 유의성 확보된 연구 분석
- **처리시간**: 24시간 내 (보통 6-12시간)  
- **비용**: 50% 할인
- **특징**: 전수 분석이므로 인간 코딩 검증 불필요

#### `full` (전체 데이터)
- **용도**: 전체 데이터셋 완전 분석
- **처리시간**: 24시간 내 (보통 12-24시간)
- **비용**: 50% 할인
- **특징**: 전수 분석이므로 인간 코딩 검증 불필요

## 🛠️ 새로 추가된 기능

### 1. **자동 결과 처리**
- 배치 완료 자동 감지
- 결과 다운로드 및 파싱
- RDS/CSV 파일 자동 저장
- 분석 이력 자동 등록

### 2. **통합 모니터링**
```r
# 06_batch_monitor.R 실행 후 메뉴 선택:
# 1. 배치 작업 목록 보기
# 2. 특정 배치 상태 확인  
# 3. ✨ 결과 다운로드 및 처리 (신규)
# 4. 종료
```

### 3. **에러 처리 강화**
- 네트워크 오류 자동 재시도
- 부분 실패 시 복구 메커니즘
- 안전한 상태 확인 시스템

## 💡 주요 사용법

### 🚀 가장 간단한 방법 (추천)
```r
source("batch_utils.R")
result <- run_batch_with_monitoring("code_check")  # 테스트
result <- run_batch_with_monitoring("sampling")    # 전수분석
```

### 📊 대화형 모니터링
```r
source("06_batch_monitor.R")
interactive_batch_manager()
```

### 🔧 고급 제어
```r
# 제출만 (모니터링 없이)
batch_info <- run_batch_emotion_analysis("sampling", submit_only = TRUE)

# 나중에 재개
result <- resume_batch_monitoring(batch_info$batch_name)
```

## ⚠️ 중요 안내

### **배치 vs 일반 처리**
- **배치 처리**: 전수 분석용, ❌ 신뢰도 분석 불필요
- **일반 처리**: 샘플링 후 ✅ 인간 코딩 검증 필요

### **모드 선택 가이드**  
- **방법론 검증**: `code_check`, `pilot`
- **최종 연구 분석**: `sampling`, `full`

## 배치 처리 vs 실시간 처리 비교

| 항목 | 실시간 처리 (03스크립트) | 배치 처리 (04스크립트) |
|------|-------------|-----------|
| **비용** | 표준 요금 | **50% 절약** |
| **처리 속도** | 즉시 | 24시간 내 |
| **최대 요청** | 분당 제한 | 10,000개 배치 |
| **적용 사례** | 즉시 결과 필요 | 대량 사전 처리 |
| **안정성** | 네트워크 의존 | 높은 안정성 |

## 사용 방법

### 1. 기본 배치 처리 실행

```r
# 04_배치처리_감정분석.R 실행
source("04_배치처리_감정분석.R")

# 대화형 모드 선택으로 실행
result <- run_batch_emotion_analysis()

# 또는 특정 모드로 실행
result <- run_batch_emotion_analysis("sampling")  # 표본 분석
result <- run_batch_emotion_analysis("full")      # 전체 분석
```

### 2. 배치 작업 모니터링

```r
# 배치 모니터링 도구 실행
source("batch_monitor.R")

# 대화형 관리자 실행
interactive_batch_manager()

# 또는 개별 명령어
monitor <- BatchMonitor$new()
monitor$list_batch_jobs()              # 작업 목록
monitor$get_batch_status("batch_name") # 상태 확인
monitor$cancel_batch_job("batch_name") # 작업 취소
```

## 배치 처리 프로세스

### 단계별 진행 과정

1. **데이터 준비**
   - 기존 분석 결과 필터링
   - 중복 분석 방지
   - JSONL 형식 배치 파일 생성

2. **파일 업로드**
   - Google Cloud Storage 업로드
   - Resumable Upload 지원 (2GB까지)

3. **배치 작업 생성**
   - Gemini API 배치 엔드포인트 호출
   - 작업 ID 반환

4. **진행 상황 모니터링**
   - 5분 간격 상태 확인
   - 실시간 로그 출력
   - 최대 26시간 대기

5. **결과 처리**
   - JSONL 결과 다운로드
   - JSON 파싱 및 데이터프레임 변환
   - 기존 데이터와 병합

6. **저장 및 이력 관리**
   - RDS/CSV 파일 저장
   - 분석 이력 등록
   - 중복 방지 데이터 업데이트

## 배치 작업 상태

| 상태 | 설명 |
|------|------|
| `JOB_STATE_PENDING` | 작업 대기 중 |
| `JOB_STATE_RUNNING` | 처리 진행 중 |
| `JOB_STATE_SUCCEEDED` | ✅ 성공 완료 |
| `JOB_STATE_FAILED` | ❌ 실패 |
| `JOB_STATE_CANCELLED` | ⚠️ 사용자 취소 |

## 파일 구조

```
📁 emotion_analysis/
├── 04_배치처리_감정분석.R      # 메인 배치 처리 스크립트
├── batch_monitor.R             # 배치 작업 모니터링 도구
├── config.R                    # 배치 설정 포함
└── results/
    └── analysis_results_BATCH_sampling_XXXitems.RDS
```

## 설정 옵션

`config.R`의 `BATCH_CONFIG`에서 설정 가능:

```r
BATCH_CONFIG <- list(
  model_name = "gemini-2.5-flash",     # 배치 전용 모델
  max_batch_size = 10000,              # 배치당 최대 요청
  max_file_size_mb = 2000,             # 파일 크기 제한
  poll_interval_seconds = 300,         # 상태 확인 간격
  max_wait_hours = 26,                 # 최대 대기 시간
  cost_savings_percentage = 50         # 비용 절약률
)
```

## 비용 계산 예시

### 예시: 10,000개 텍스트 분석

**실시간 처리**:
- 비용: $20.00 (가정)
- 시간: 약 3시간 (분당 제한)
- 안정성: 네트워크 의존

**배치 처리**:
- 비용: **$10.00 (50% 절약)**
- 시간: 6-24시간
- 안정성: 높음 (재시도 내장)

**절약 효과**: $10.00 절약, 더 안정적인 처리

## 권장 사용 사례

### ✅ 배치 처리 적합한 경우

- **대량 데이터 사전 처리** (1,000개 이상)
- **비용 최적화가 중요한 경우**
- **연구용 데이터 분석**
- **정기적인 배치 작업**
- **안정성이 중요한 분석**

### ❌ 실시간 처리가 필요한 경우

- **즉시 결과가 필요한 경우**
- **소량 데이터** (100개 미만)
- **대화형 분석**
- **프로토타이핑 및 테스트**

## 문제 해결

### 일반적인 문제

1. **API 키 오류**
   ```bash
   export GEMINI_API_KEY="your-api-key"
   ```

2. **파일 크기 초과**
   - 데이터를 여러 배치로 분할
   - `max_batch_size` 줄이기

3. **배치 작업 실패**
   ```r
   # 상태 확인
   monitor$get_batch_status("batch_name")
   
   # 실패 원인 확인
   # 로그에서 오류 메시지 확인
   ```

4. **긴 대기 시간**
   - 24시간은 최대 시간 (보통 더 빠름)
   - 시스템 부하에 따라 변동
   - 작은 배치로 분할 고려

### 로그 확인

```r
# 로그 파일 위치
tail -f logs/analysis.log

# 특정 배치 작업 로그 필터링
grep "BATCH" logs/analysis.log
```

## 모범 사례

1. **데이터 준비**
   - 중복 제거 확인
   - 빈 텍스트 필터링
   - 적절한 배치 크기 선택

2. **모니터링**
   - 정기적인 상태 확인
   - 로그 모니터링
   - 오류 처리 준비

3. **비용 관리**
   - 배치 크기 최적화
   - 불필요한 재분석 방지
   - 비용 추적

4. **백업 및 복구**
   - 중간 파일 보존
   - 결과 백업
   - 재시작 가능한 구조

## 다음 단계

1. **04_배치처리_감정분석.R** 실행하여 첫 배치 작업 시작
2. **batch_monitor.R**로 진행 상황 모니터링
3. 완료 후 기존 03번 스크립트와 결과 비교
4. 비용 및 시간 효율성 평가

## 지원 및 문의

- 📧 배치 처리 관련 문의: 로그 파일과 함께 문의
- 📖 추가 문서: `BATCH_PROCESSING_ADVANCED.md` (고급 사용법)
- 🔧 문제 해결: `batch_monitor.R`의 진단 기능 활용