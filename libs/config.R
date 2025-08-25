# 프로젝트 설정 파일
# 모든 설정값을 중앙에서 관리

# =============================================================================
# 프롬프트 설정 (감정분석용)
# =============================================================================
# 
# 📝 프롬프트 수정 방법:
# 1. 아래 PROMPT_CONFIG의 각 항목을 직접 수정
# 2. base_instructions: 기본 시스템 프롬프트 (역할, 지시사항)
# 3. comment_task, post_task: 댓글/게시글 분석 작업 지시
# 4. *_header: 각 섹션의 헤더 텍스트
# 5. 수정 후 프로젝트 재실행하면 새 프롬프트 적용됨
#
# ⚠️ 주의: base_instructions의 감정 목록이나 PAD 모델 부분을 수정할 경우 
#          JSON 스키마나 결과 파싱 로직도 함께 수정해야 할 수 있습니다.
#

PROMPT_CONFIG <- list(
  # 공통 기본 프롬프트 (일반분석과 배치분석 모두 사용)
  base_instructions = '## 역할: 리서치 보조원
## 대상: 초등교사 커뮤니티 텍스트

## 지시:
1. 원본 게시글 맥락 고려하여 댓글 감정 분석

2. **플루치크 8개 기본감정 점수(0.00-1.00)**:
   기쁨(↔슬픔), 신뢰(↔혐오), 공포(↔분노), 놀람(↔기대)
   슬픔(↔기쁨), 혐오(↔신뢰), 분노(↔공포), 기대(↔놀람)

3. **PAD 점수(-1.00~1.00)**:
   P(Pleasure): 긍정성
   A(Arousal): 활성화 
   D(Dominance): 개인 외적 통제감 - 환경/상황/타인과의 관계에서 
                 영향력 행사 및 통제력에 대한 주관적 인식
                 (※내적 감정조절 능력과 구별)

4. 최고점수 감정을 지배감정으로 선정

5. 플루치크+PAD 종합하여 복합감정 명명

6. 텍스트 근거로 추론과정 제시

## 주의사항:
- 대립감정 동시 고득점 불가
- 0.3이상 감정들로 복합감정 구성
- 교사 커뮤니티 맥락 반영',

  # 배치 전용 JSON 출력 지시 (기본 프롬프트에 추가됨)
  batch_json_instruction = '

## 중요: 응답은 반드시 유효한 JSON 형식으로만 출력하세요. 마크다운이나 다른 텍스트 없이 JSON만 출력하세요.

## JSON 구조:
{
  "plutchik_emotions": {
    "기쁨": 0.00, "신뢰": 0.00, "공포": 0.00, "놀람": 0.00,
    "슬픔": 0.00, "혐오": 0.00, "분노": 0.00, "기대": 0.00
  },
  "PAD": {"P": 0.00, "A": 0.00, "D": 0.00},
  "dominant_emotion": "감정명",
  "complex_emotion": "복합감정명",
  "rationale": {
    "emotion_scores": "점수근거",
    "PAD_analysis": "PAD근거", 
    "complex_emotion_reasoning": "복합감정근거"
  }
}',
  
  # 댓글 분석용 작업 지시
  comment_task = "## 분석 과업: '원본 게시글' 맥락을 고려하여 '분석할 댓글'의 감정을 분석.",
  
  # 게시글 분석용 작업 지시  
  post_task = "## 분석 과업: 다음 '게시글'의 감정을 분석.",
  
  # 섹션 헤더
  context_header = "# 원본 게시글 (맥락)",
  comment_header = "# 분석할 댓글 (분석 대상)",
  post_header = "# 분석할 게시글 (분석 대상)"
)

# =============================================================================
# API 설정 (gemini.R 패키지 사용)
# =============================================================================
API_CONFIG <- list(
  model_name = "2.5-flash",  # gemini.R 패키지 호환 모델
  temperature = 0.25,
  top_p = 0.85,
  rate_limit_per_minute = 3900,
  wait_time_seconds = 1,
  max_retries = 5
)

# 테스트 설정  
TEST_CONFIG <- list(
  model_name = "2.5-flash",  # gemini.R 패키지 호환 모델
  temperature = 0.25,
  top_p = 0.85,
  max_retries = 3
)

# 배치 처리 설정
BATCH_CONFIG <- list(
  # 모델 및 API 설정
  model_name = "gemini-2.5-flash",                # 배치 모드 지원 모델
  temperature = 0.25,                        # 온도 설정
  top_p = 0.85,                             # Top-p 설정
  #max_output_tokens = 2048,                 # 최대 출력 토큰
  
  # 배치 제한 설정
  max_batch_size = 100000,                   # 배치당 최대 요청 수
  max_file_size_mb = 2000,                  # 최대 파일 크기 (2GB)
  
  # 모니터링 설정
  poll_interval_seconds = 30,              # 상태 확인 간격 (5분)
  max_wait_hours = 26,                      # 최대 대기 시간 (26시간)
  detailed_logging = TRUE,                  # 상세 로깅 활성화
  
  # 비용 및 성능 설정
  cost_savings_percentage = 50,             # 비용 절약률 (표시용)
  expected_processing_hours = 24,           # 예상 처리 시간
  
  # 자동화 설정
  enable_batch_mode = TRUE,                 # 배치 모드 활성화
  auto_retry_failed = TRUE,                 # 실패 시 자동 재시도
  auto_download_results = TRUE,             # 완료 시 자동 다운로드
  auto_parse_results = TRUE,                # 자동 결과 파싱
  
  # 파일 관리 설정
  save_intermediate_files = TRUE,           # 중간 파일 저장 여부
  cleanup_temp_files = TRUE,                # 임시 파일 정리
  backup_batch_requests = TRUE,             # 배치 요청 백업
  
  # 알림 설정
  notify_on_completion = FALSE,             # 완료 시 알림 (추후 구현)
  email_notifications = FALSE,              # 이메일 알림 (추후 구현)
  
  # 모니터링 관련 설정
  base_url = "https://generativelanguage.googleapis.com/v1beta",  # API 베이스 URL
  status_check_delay_seconds = 2,           # 상태 확인 후 대기 시간
  file_name_format = "%Y%m%d_%H%M%S"        # 결과 파일명 시간 형식
)

# Python 배치 처리 설정
PYTHON_CONFIG <- list(
  use_python_batch = FALSE,                     # Python 배치 처리 사용 여부 (기본: R 방식 사용)
  batch_processor_script = "libs/batch_processor.py",  # Python 배치 처리 스크립트 경로
  default_model = "gemini-2.5-flash",          # Python 배치용 기본 모델
  default_temperature = 0.25,                  # 기본 온도 설정
  required_packages = c("google-generativeai", "pandas", "json"),  # 필수 패키지
  auto_install_packages = FALSE,               # 자동 패키지 설치 여부
  fallback_to_r = TRUE                         # Python 실패 시 R 방식으로 폴백
)

# 분석 설정
ANALYSIS_CONFIG <- list(
  # 기본 샘플링 설정
  sample_post_count = 10,                    # 기존 방식 (하위 호환용)
  
  # 적응형 샘플링 설정 (표집 공식 대응)
  enable_adaptive_sampling = TRUE,           # 적응형 샘플링 활성화
  target_sample_size = 384,                  # 목표 샘플 크기 (표집 공식)
  min_posts_start = 2,                       # 최소 시작 게시글 수
  max_posts_limit = 1000,                    # 최대 게시글 수 제한
  max_iteration = 10,                        # 최대 반복 횟수
  increment_step = 1,                        # 게시글 수 증가 단위
  safety_buffer = 0.15,                      # 안전 버퍼 (15% 여유분, 필터링 손실 대비)
  
  # 샘플 크기 제어 설정
  max_human_coding_size = 400,               # 인간 코딩 최대 샘플 크기
  enable_sample_replacement = TRUE,          # 과도한 샘플 교체 활성화
  replacement_method = "ask",                # "ask", "random", "balanced", "quality"
  
  # 사용자 선택 설정
  analysis_mode = "ask",                     # "ask", "sample", "full"
  
  target_gdrive_folder = "emotion_analysis_results"
)

# 파일 경로
PATHS <- list(
  data_dir = "data",
  results_dir = "results",
  source_data = "data/data_collection.csv",
  prompts_data = "data/prompts_ready.RDS",
  functions_file = "libs/functions.R"
)

# 파일명 설정
FILE_CONFIG <- list(
  include_timestamp = TRUE,                  # 파일명에 시간 포함 여부
  timestamp_format = "%Y%m%d_%H%M%S",       # 시간 형식
  timestamp_separator = "_"                  # 시간과 파일명 사이 구분자
)

# 로깅 설정
LOG_CONFIG <- list(
  enable_logging = TRUE,
  log_level = "INFO",  # DEBUG, INFO, WARN, ERROR
  log_file = "logs/analysis.log"
)

# 복구 시스템 설정
RECOVERY_CONFIG <- list(
  enable_checkpoints = TRUE,
  checkpoint_dir = "checkpoints",
  max_checkpoint_age_hours = 24,
  cleanup_days = 7,
  batch_size = 100,  # 배치 처리 시 기본 크기
  auto_recover = TRUE  # 자동 복구 시도 여부
)

# 인간 코딩 설정
HUMAN_CODING_CONFIG <- list(
  enable_human_coding = TRUE,           # 인간 코딩 활성화
  num_coders = 4,                      # 코더 수
  upload_sample_only = TRUE,           # 샘플링 분석만 업로드
  min_sample_size = 10,                # 최소 샘플 크기 (테스트용으로 10개)
  coder_names = c("coder1", "coder2", "coder3", "coder4"),
  gdrive_folder = "human_coding_sheets", # 구글 드라이브 폴더명
  sheet_template = list(
    emotions = c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대"), # 플루치크 8대 기본감정
    agree_options = c("동의", "비동의")  # 체크박스로 간소화
  )
)