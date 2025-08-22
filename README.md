# 초등교사 커뮤니티 감정분석 시스템

초등교사 커뮤니티 텍스트 데이터에 대한 **플루치크 8대 감정** 및 **PAD 모델** 기반 고급 감정분석 파이프라인

[![R](https://img.shields.io/badge/R-4.5.1+-blue.svg)](https://www.r-project.org/)
[![Gemini AI](https://img.shields.io/badge/Gemini-2.5%20Flash%20Lite-orange.svg)](https://ai.google.dev/)
[![License](https://img.shields.io/badge/License-Academic%20Research%20Only-red.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-Repository-blue.svg)](https://github.com/rubato103/emotion-analysis-indischool)

## 주요 특징

### 고도화된 감정분석 모델
- **플루치크 8대 감정**: 기쁨↔슬픔, 신뢰↔혐오, 공포↔분노, 놀람↔기대
- **PAD 3차원 모델**: Pleasure(긍정성), Arousal(활성화), Dominance(통제감)
- **복합감정 추론**: 다중 감정의 조합으로 미묘한 감정 상태 분석
- **맥락 인식**: 원본 게시글과 댓글의 상호작용 맥락 고려

### 확장 가능한 처리 아키텍처
- **적응형 샘플링**: 목표 크기 자동 달성 및 게시글-댓글 맥락 보존
- **배치 처리**: Gemini API 배치 모드로 대규모 데이터 효율적 처리 (50% 비용 절감)
- **병렬 처리**: 멀티코어 활용으로 분석 속도 향상
- **자동 복구**: 실패 시 중단점부터 재개

### 신뢰도 검증 시스템
- **인간 코더 비교**: 4명 코더 대상 자동 구글 시트 생성
- **Krippendorff's Alpha**: 코더간 신뢰도 통계 분석
- **품질 보증**: 실시간 결과 검증 및 오류 탐지

## 빠른 시작

### 1. 환경 설정
```r
# R 환경 및 패키지 자동 설치
source("00_setup_r_environment.R")
```

### 2. API 키 설정 (시스템 환경변수 권장)
**자세한 설정 가이드**: [`GEMINI_API_SETUP.md`](GEMINI_API_SETUP.md) 참조

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

# 2. 배치 상태 모니터링 및 결과 처리
source("06_batch_monitor.R") 
# → 자동 상태 확인, 완료 시 결과 다운로드 및 파싱
```

### 신뢰도 검증 워크플로우
```r
# 인간 코더간 신뢰도 분석 (Krippendorff's Alpha)
source("05_reliability_analysis.R")
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
│   ├── config.R                # 통합 설정 관리
│   ├── functions.R             # 감정분석 핵심 함수
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
    ├── 00_setup_r_environment.R     # 환경 초기화
    ├── 01_data_loading_and_prompt_generation.R  # 데이터 전처리
    ├── 02_single_analysis_test.R    # API 연결 테스트
    ├── 03_full_emotion_analysis.R   # 일반 분석 (실시간)
    ├── 05_batch_request.R           # 배치 요청 생성
    ├── 05_reliability_analysis.R    # 신뢰도 검증
    └── 06_batch_monitor.R           # 배치 모니터링
```

## 핵심 설정

### 프롬프트 설정 (`libs/config.R`)
```r
PROMPT_CONFIG <- list(
  base_instructions = '역할: 리서치 보조원, 대상: 초등교사 커뮤니티...',
  comment_task = '원본 게시글 맥락을 고려하여 댓글의 감정을 분석',
  # 모든 프롬프트를 중앙에서 관리
)
```

### API 및 분석 설정
```r
API_CONFIG <- list(
  model_name = "2.5-flash-lite",     # Gemini 2.5 Flash Lite
  temperature = 1.0,
  rate_limit_per_minute = 1000,
  batch_enabled = TRUE               # 배치 처리 활성화
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
```

### 로그 및 디버깅
```r
# 로그 레벨 설정 (libs/config.R)
LOG_CONFIG$log_level <- "DEBUG"  # ERROR|WARN|INFO|DEBUG

# 로그 파일 확인
file.show("logs/analysis.log")

# 중간 결과 확인
list.files("checkpoints/", pattern = "\\.RDS$")
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

---

**팁**: 첫 사용 시 `코드 점검` 모드로 API 연결을 확인한 후, `파일럿 연구`로 소규모 테스트를 거쳐 본격적인 분석을 시작하세요.
