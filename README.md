# 초등교사 커뮤니티 감정분석 시스템

초등교사 커뮤니티 텍스트 데이터에 대한 **플루치크 8대 기본감정** 및 **PAD 모델** 기반 고급 감정분석 파이프라인

[![R](https://img.shields.io/badge/R-4.5.1+-blue.svg)](https://www.r-project.org/)
[![Gemini AI](https://img.shields.io/badge/Gemini-2.5%20Flash-orange.svg)](https://ai.google.dev/)
[![License](https://img.shields.io/badge/License-Academic%20Research%20Only-red.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-Repository-blue.svg)](https://github.com/rubato103/emotion-analysis-indischool)

> **🚀 최신 업데이트 (2025.08.26)**
> - 배치 처리 시스템 완전 안정화 및 JSON 파싱 최적화 ✅
> - Windows R 실행 환경 개선 (PowerShell 기반) ✅  
> - 플루치크 8대 기본감정 + PAD 모델 통합 지원 ✅
> - Python 배치 처리 통합 및 R 폴백 시스템 구축 ✅
> - 통합 설정 관리 시스템 (config.R) 중앙화 ✅

## 주요 특징

### 🎭 고도화된 감정분석 모델
- **플루치크 8대 기본감정**: 기쁨↔슬픔, 신뢰↔혐오, 공포↔분노, 놀람↔기대
- **PAD 3차원 모델**: Pleasure(긍정성), Arousal(활성화), Dominance(외적 통제감)
- **복합감정 추론**: 다중 감정의 조합으로 미묘한 감정 상태 분석
- **맥락 인식**: 원본 게시글과 댓글의 상호작용 맥락 고려
- **구조화된 출력**: JSON 기반 정형화된 분석 결과

### ⚡ 확장 가능한 처리 아키텍처  
- **배치 처리**: Gemini API 배치 모드로 대규모 데이터 효율적 처리 (50% 비용 절감)
- **적응형 샘플링**: 목표 크기 자동 달성 및 게시글-댓글 맥락 보존
- **통합 파싱 시스템**: 일반분석과 배치분석 공통 JSON 파싱 로직
- **자동 복구**: 실패 시 중단점부터 재개
- **Windows 최적화**: PowerShell 기반 안정적인 R 실행환경

### 🔬 신뢰도 검증 시스템
- **인간 코더 비교**: 4명 코더 대상 자동 구글 시트 생성
- **Krippendorff's Alpha**: 코더간 신뢰도 통계 분석
- **품질 보증**: 실시간 결과 검증 및 오류 탐지

## 빠른 시작

### 1. 환경 설정
```r
# R 환경 및 패키지 자동 설치
source("setup/install_packages.R")
```

### 2. API 키 설정 (시스템 환경변수 권장)
**자세한 설정 가이드**: [`GEMINI_API_SETUP.md`](GEMINI_API_SETUP.md) 참조

**API 키 확인 방법**:
```r
# 환경변수 설정 상태 확인
source("libs/config.R")
cat("API 키 설정:", if(Sys.getenv("GEMINI_API_KEY") != "") "✅ 정상" else "❌ 미설정", "\n")
```

**Windows (권장 방법)**:
1. 시작 메뉴 → "환경 변수" 검색
2. "시스템 환경 변수 편집" → "환경 변수" 버튼
3. 사용자 변수에서 "새로 만들기"
4. 변수 이름: `GEMINI_API_KEY` / 변수 값: `your_api_key_here`

**macOS/Linux**:
```bash
echo 'export GEMINI_API_KEY="your_api_key_here"' >> ~/.zshrc
source ~/.zshrc
```

### 3. 데이터 준비
`data/data_collection.csv` 파일을 다음 구조로 준비:
```csv
post_id,comment_id,구분,title,content,depth,views,likes
1,NA,게시글,제목,내용,0,100,5
1,1,댓글,NA,댓글내용,1,NA,2
```

## 워크플로우

### 기본 분석 워크플로우
```r
# 1. 데이터 전처리 및 프롬프트 생성
source("01_data_loading_and_prompt_generation.R")

# 2. API 연결 테스트 (1개 샘플)
source("02_single_analysis_test.R")

# 3. 전체 분석 실행 (4가지 모드)
source("03_full_emotion_analysis.R")
# → 코드 점검 (1개), 파일럿 (5개), 표본 분석 (384+개), 전체 분석 (모든 데이터)
```

### 배치 처리 워크플로우 (권장: 대용량 데이터)
```r
# 1. 배치 요청 생성 및 제출
source("05_batch_request.R")
# → JSONL 파일 생성 및 Gemini API 배치 제출
# → Python 배치 처리 시도 → R 폴백 시스템

# 2. 배치 상태 모니터링 및 결과 처리
source("06_batch_monitor.R") 
# → 자동 상태 확인, 완료 시 결과 다운로드 및 파싱
# → 통합 JSON 파싱 시스템으로 안정적 결과 처리
```

### 신뢰도 검증 워크플로우
```r
# 인간 코더간 신뢰도 분석 (Krippendorff's Alpha)
source("04_reliability_analysis.R")
# → 4명 코더 체크박스 시트 자동 생성 및 분석
```

## 📁 프로젝트 구조

```
emotion-analysis-indischool/
├── data/
│   ├── data_collection.csv      # 원본 데이터 (140MB+)
│   └── prompts_ready.RDS       # 전처리된 프롬프트 (80MB+)
├── results/                 # 분석 결과 (RDS + CSV + 구글시트)
├── logs/                    # 상세 실행 로그
├── libs/                    # 핵심 라이브러리
│   ├── config.R                # 통합 설정 관리 (PROMPT_CONFIG, API_CONFIG, BATCH_CONFIG, PYTHON_CONFIG)
│   ├── functions.R             # 감정분석 핵심 함수 (통합 JSON 파싱)
│   └── utils.R                 # 범용 유틸리티 함수
├── modules/                 # 기능별 모듈
│   ├── adaptive_sampling.R     # 적응형 샘플링 엔진
│   ├── analysis_tracker.R      # 분석 진행 추적
│   ├── human_coding.R          # 인간 코더 시스템
│   ├── reanalysis_manager.R    # 재분석 관리
│   ├── recovery_system.R       # 실패 복구 시스템
│   └── sample_replacement.R    # 샘플 최적화
├── setup/                   # 설치 및 테스트
│   ├── install_packages.R      # 패키지 자동 설치
│   └── test_prompt_consistency.R  # 프롬프트 일관성 검증
├── archive/                 # 버전 관리 및 백업
└── 주요 스크립트/
    ├── 01_data_loading_and_prompt_generation.R  # 데이터 전처리
    ├── 02_single_analysis_test.R    # API 연결 테스트
    ├── 03_full_emotion_analysis.R   # 일반 분석 (실시간)
    ├── 04_reliability_analysis.R    # 신뢰도 검증 (Krippendorff's Alpha)
    ├── 05_batch_request.R           # 배치 요청 생성 (Python/R 통합)
    └── 06_batch_monitor.R           # 배치 모니터링 (안정화된 파싱)
```

## 핵심 설정

### 통합 설정 관리 (`libs/config.R`)
```r
# 프롬프트 설정 (감정분석 지시사항)
PROMPT_CONFIG <- list(
  base_instructions = '## 역할: 리서치 보조원\n## 대상: 초등교사 커뮤니티 텍스트...',
  batch_json_instruction = '\n\n## 중요: 응답은 반드시 유효한 JSON 형식으로만 출력하세요...',
  comment_task = '원본 게시글 맥락을 고려하여 댓글의 감정을 분석',
  # 모든 프롬프트를 중앙에서 관리
)

# Python 배치 처리 설정
PYTHON_CONFIG <- list(
  use_python_batch = FALSE,         # 기본값: R 방식 사용
  fallback_to_r = TRUE              # Python 실패 시 R로 폴백
)
```

### API 및 배치 설정  
```r
API_CONFIG <- list(
  model_name = "2.5-flash",          # gemini.R 패키지 호환
  temperature = 0.25,                # 낮은 온도로 일관성 향상
  top_p = 0.85,
  rate_limit_per_minute = 3900       # 안정적 속도 제한
)

BATCH_CONFIG <- list(
  model_name = "gemini-2.5-flash",   # 배치 모드 지원 모델
  max_batch_size = 100000,           # 배치당 최대 요청 수
  auto_retry_failed = TRUE,          # 실패 시 자동 재시도
  auto_download_results = TRUE       # 완료 시 자동 다운로드
)

ANALYSIS_CONFIG <- list(
  sample_post_count = 5,              # 파일럿 모드 게시글 수
  target_sample_size = 384,           # 표본 분석 목표 크기
  enable_adaptive_sampling = TRUE,    # 적응형 샘플링 사용
  analysis_mode = "ask"               # ask|code_check|pilot|sampling|full
)
```

## 감정분석 모델

### 플루치크 8대 감정 (0.00-1.00 점수)
| 감정 쌍 | 설명 |
|---------|------|
| **기쁨 ↔ 슬픔** | 긍정적 기분 상태 vs 부정적 기분 상태 |
| **신뢰 ↔ 혐오** | 수용과 확신 vs 거부와 반감 |
| **공포 ↔ 분노** | 회피 욕구 vs 공격적 반응 |
| **놀람 ↔ 기대** | 예상치 못한 반응 vs 예측과 기대 |

### PAD 3차원 모델 (-1.00~1.00 점수)
- **P (Pleasure)**: 긍정성, 쾌락 정도
- **A (Arousal)**: 활성화, 각성 수준  
- **D (Dominance)**: 환경/상황/타인과의 관계에서 영향력 행사 및 통제감

### 🎭 복합감정 추론
PAD 점수와 기본감정을 종합하여 다음과 같은 복합감정 도출:
- `기쁨+놀람+높은P+높은A` → "기쁜 놀라움" 
- `슬픔+공포+낮은P+높은A` → "불안한 슬픔"

## 분석 모드

| 모드 | 데이터 크기 | 용도 | 처리 방식 |
|------|-------------|------|-----------|
| **코드 점검** | 1개 샘플 | API 연결 확인 | 실시간 |
| **파일럿 연구** | 5개 게시글 | 예비 분석 | 실시간 |
| **표본 분석** | 384개+ | 통계적 분석 | 실시간/배치 |
| **전체 분석** | 전체 데이터 | 완전 분석 | 배치 권장 |

## 결과 해석

### 출력 데이터 구조
```r
# 기본 감정 점수
기쁨, 슬픔, 신뢰, 혐오, 공포, 분노, 놀람, 기대

# PAD 모델 점수  
P, A, D

# 분석 결과
dominant_emotion        # 최고 점수 감정
PAD_complex_emotion     # PAD 기반 복합 감정
rationale              # AI 분석 근거
confidence_score       # 분석 신뢰도
unexpected_emotions    # 예상 외 감정
```

### 저장 형식
- **로컬**: `results/analysis_results_[MODE]_[COUNT]items_[TIMESTAMP].RDS/CSV`
- **클라우드**: 구글 시트 자동 업로드 (인간 코딩용)
- **로그**: `logs/analysis.log` 상세 실행 기록

## 고급 기능

### 적응형 샘플링
```r
# 게시글-댓글 맥락을 유지하면서 목표 크기 달성
adaptive_sampling(data, target_size = 384, min_posts = 2, max_posts = 1000)
```

### 배치 처리 (50% 비용 절감)
```r
# 대용량 데이터를 JSON Lines 형태로 변환 후 배치 제출
run_batch_request(sample_mode = "sampling")  # 05_batch_request.R
interactive_batch_manager()                  # 06_batch_monitor.R
```

### 실시간 모니터링
```r
# 분석 진행 상황 추적
tracker <- AnalysisTracker$new()
tracker$start_analysis(mode = "pilot", total_items = 181)
tracker$update_progress(completed = 50, failed = 2)
```

### 🏥 자동 복구 시스템
```r
# 실패 지점에서 자동 재개
with_recovery("분석단계", "03_full_emotion_analysis", function() {
  # 분석 코드
}, force_rerun = FALSE)
```

## 🧪 신뢰도 검증

### 👥 인간 코더 시스템
- **자동 구글 시트 생성**: 4명 코더용 개별 시트
- **체크박스 인터페이스**: 감정 선택 UI 자동 생성
- **로컬 백업**: CSV 형태로 추가 저장

### 통계적 검증
```r
# Krippendorff's Alpha 계산 (코더간 신뢰도)
calculate_krippendorff_alpha(data_matrix, level = "nominal")
# α > 0.8: 높은 신뢰도, α > 0.67: 허용 가능
```

## 시스템 요구사항

### 필수 요구사항
- **R 4.5.1+** 
- **Gemini API 키** (시스템 환경변수 설정, [`GEMINI_API_SETUP.md`](GEMINI_API_SETUP.md) 참조)
- **메모리**: 최소 8GB RAM (대용량 데이터 시)
- **저장공간**: 1GB+ (결과 파일 저장)

### 권장 사항
- **네트워크**: 안정적인 인터넷 연결 (API 호출)
- **CPU**: 멀티코어 (병렬 처리 활용)
- **구글 계정**: 구글 시트/드라이브 연동

## 문제 해결

### 일반적인 문제

#### 1. API 키 오류
```r
# 시스템 환경변수 확인
Sys.getenv("GEMINI_API_KEY")

# API 키 설정 상태 확인
if (Sys.getenv("GEMINI_API_KEY") != "") {
  cat("[OK] API 키가 정상적으로 설정되었습니다.\n")
} else {
  cat("[ERROR] API 키가 설정되지 않았습니다.\n")
  cat("설정 가이드: GEMINI_API_SETUP.md 파일을 참조하세요.\n")
}

# 임시 설정 (재시작 시 사라짐)
Sys.setenv(GEMINI_API_KEY = "your_api_key_here")
```

#### 2. 메모리 부족
```r
# libs/config.R에서 샘플 크기 조정
ANALYSIS_CONFIG$sample_post_count <- 3      # 파일럿 모드 게시글 수 감소
ANALYSIS_CONFIG$target_sample_size <- 100   # 표본 분석 목표 크기 감소

# 배치 크기 조정
BATCH_CONFIG$max_batch_size <- 1000         # 배치 크기 감소
```

#### 3. 패키지 설치 문제
```r
# CRAN 미러 설정
options(repos = c(CRAN = "https://cran.seoul.go.kr/"))
source("setup/install_packages.R")
```

#### 4. 구글 인증 문제
```r
# 인증 재설정
googlesheets4::gs4_deauth()
googlesheets4::gs4_auth()
googledrive::drive_deauth()
googledrive::drive_auth()
```

#### 5. 배치 처리 실패
```r
# 배치 상태 수동 확인
source("06_batch_monitor.R")
read_batch_jobs()  # 현재 배치 작업 확인

# Python 배치 실패 시 R 폴백 설정 확인
source("libs/config.R")
cat("Python 배치:", PYTHON_CONFIG$use_python_batch, 
    "| R 폴백:", PYTHON_CONFIG$fallback_to_r, "\n")
```

### 로그 및 디버깅
```r
# 로그 레벨 설정 (libs/config.R)
LOG_CONFIG$log_level <- "DEBUG"  # ERROR|WARN|INFO|DEBUG

# 로그 파일 확인
file.show("logs/analysis.log")

# 중간 결과 확인
list.files("results/", pattern = "analysis_results.*\\.RDS$")
list.files("results/", pattern = "batch_parsed.*\\.RDS$")

# 현재 배치 작업 상태
source("06_batch_monitor.R")
read_batch_jobs()
```

## 📞 지원 및 문의

- **로그 확인**: `logs/analysis.log` 파일 참조
- **백업 데이터**: `archive/` 폴더에서 이전 버전 확인  
- **설정 조정**: `libs/config.R`에서 모든 매개변수 중앙 관리
- **이슈 리포트**: 실행 로그와 함께 문의

## 라이센스 및 사용 제한

**중요: 학술 연구 전용 시스템**

이 감정분석 시스템은 **학술 연구 목적으로만 사용**이 허용됩니다:

### 허용 사용 범위
- **논문 작성 및 발표**: 학술 논문의 연구 방법론 및 결과 도출
- **연구 재현성**: 기발표 논문의 방법론 검증 및 재현 실험  
- **학술 발표**: 학회, 세미나, 연구 모임에서의 연구 결과 공유
- **교육 목적**: 대학원 수업 및 연구 방법론 교육 자료

### 금지 사용 범위
- **상업적 이용**: 영리 목적의 서비스 개발 및 운영
- **정책 결정**: 교육정책 수립이나 행정 결정의 근거 자료
- **개인정보 분석**: 특정 개인의 감정 상태 진단 및 평가
- **무단 2차 배포**: 시스템 구조나 알고리즘의 무단 복제 및 배포

### 인용 의무
본 시스템을 사용한 연구 결과 발표 시 다음과 같이 인용해주세요:

**영문**:
```
Yang, Y. (2025). Advanced Emotion Analysis Pipeline for Elementary Teacher Community 
using Plutchik's 8 Basic Emotions and PAD Model with Gemini 2.5 Flash Lite API. 
GitHub Repository.
```

**국문**:
```
양연동. (2025). 플루치크 8대 감정 및 PAD 모델 기반 초등교사 커뮤니티 감정분석 고급 파이프라인. 
Gemini 2.5 Flash Lite API 활용. GitHub Repository.
```

### 면책사항
- 본 시스템의 분석 결과는 연구 참고용으로만 활용해야 합니다
- AI 모델의 특성상 완벽한 분석을 보장하지 않습니다  
- 사용자는 결과 해석 시 충분한 검토와 검증을 거쳐야 합니다

## 📈 최근 개선사항 (2025.08.26)

### 🔧 시스템 안정화
- **Windows R 실행 환경**: PowerShell 기반으로 변경하여 Segmentation fault 오류 해결
- **통합 JSON 파싱**: 일반분석과 배치분석 공통 파싱 로직으로 통합하여 일관성 보장  
- **Python 배치 통합**: Python 배치 처리 시도 → R 폴백 시스템으로 안정성 향상
- **설정 중앙화**: 모든 설정을 `libs/config.R`에서 통합 관리

### ⚡ 성능 최적화
- **배치 처리**: 대용량 데이터 처리 시 50% 비용 절감 효과
- **토큰 효율성**: 프롬프트 최적화로 API 호출 비용 감소
- **자동 복구**: 실패 지점 자동 감지 및 재개 시스템

### 📊 품질 향상
- **JSON 구조 통일**: 모든 출력 형식을 일관된 JSON 스키마로 표준화
- **오류 처리 강화**: 다양한 응답 형식에 대한 견고한 파싱 로직
- **검증 시스템**: 결과 품질 자동 검증 및 이상치 탐지

---

**🚀 사용 팁**: 
- 첫 사용: `코드 점검` 모드로 API 연결 확인
- 소규모 테스트: `파일럿 연구` 모드로 5개 게시글 분석  
- 본격 분석: `표본 분석` 또는 `배치 처리` 모드 선택
- 문제 발생 시: `logs/analysis.log` 파일과 현재 배치 상태 확인
