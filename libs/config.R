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
1. 표면적 해석보다 감정의 동기를 고려하여 감정 스코어링

2. 추론 후 근거를 재검토하여 스코어 조정

3. **감정 대상 (Primary Target) 분류**:
3-1. 감정 대상을 두 가지로 구분하여 분류:
emotion_source: 감정을 유발한 원인 (6가지 범주 중 선택)
emotion_direction: 감정이 향하는 방향 (6가지 범주 중 선택)
3-2. 6가지 범주: [교사,학부모,학생,학교내 외집단(교감/교장,행정실,공무직 등),교육행정기관 및 제도,교원단체]
3-3. 이하 감정추론 전반에 감정대상의 이중구조를 고려할 것.

4. **플루치크 8개 기본감정 점수(0.00-1.00)**:
기쁨(↔슬픔): 평온→기쁨→황홀 | 만족, 즐거움, 환희, 행복감
신뢰(↔혐오): 수용→신뢰→숭배 | 믿음, 의지, 존경, 애착
공포(↔분노): 불안→공포→공황 | 걱정, 두려움, 경계, 위축
놀람(↔기대): 주의분산→놀람→경악 | 의외, 당황, 충격
슬픔(↔기쁨): 우울→슬픔→비탄 | 실망, 상실감, 애도, 절망
혐오(↔신뢰): 지루함→혐오→역겨움 | 거부감, 경멸, 반감
분노(↔공포): 짜증→분노→격노 | 화남, 분개, 적대감, 격분
기대(↔놀람): 관심→기대→경계 | 호기심, 준비, 예측, 계획

5. **플루치크 감정 조합 규칙**: 
- 감정 휠 순환 순서: 기쁨 → 신뢰 → 공포 → 놀람 → 슬픔 → 혐오 → 분노 → 기대 → (기쁨으로 순환)
- 1차 조합(인접 감정): 강한 시너지 → 명확한 복합감정 
- 2차 조합(한개 건너뛴): 보통 연결 → 복잡한 심리상태 
- 3차 조합(대극 감정): 갈등 관계 → 내적 갈등/모순 
- 0.3 이상인 감정이 여러 개일 경우, 반드시 1차, 2차, 3차 조합 규칙을 적용하여 맥락에 따라 가장 적절한 조합감정 명명

6. **PAD 점수(-1.00~1.00)**:
   P(Pleasure): 긍정성
   A(Arousal): 활성화 
   D(Dominance): 개인 외적 통제감 - 환경/상황/타인과의 관계에서 
                 영향력 행사 및 통제력에 대한 주관적 인식
                 (※내적 감정조절 능력과 구별)

7. **조합감정 (`combinated_emotion`) 명명**: 플루치크 감정 조합 규칙에 따라, 위 스코어링을 참조하여 `combinated_emotion` 필드에 조합감정의 이름을 명시합니다. (예: 경멸, 적대감)

8. **복합감정 (`complex_emotion`) 명명**: `combinated_emotion`과 PAD 점수의 맥락을 종합적으로 고려하여, 최종적인 복합감정의 이름을 `complex_emotion` 필드에 명시합니다.

9. 텍스트 근거로 추론과정 제시

## 주의사항:
- 0.3이상 감정들로 복합감정 구성
- 교사 커뮤니티 맥락 반영
- 짧은 표현: 단순하고 직관적 해석 우선
- 긴 텍스트: 복합적 감정 조합 고려
- 맥락에 따른 반어적 표현에 주의'
,

  # 공통 JSON 구조 정의 (확장된 버전)
  json_structure = '
## JSON 응답 구조:
{
  "plutchik_emotions": {
    "기쁨": 0.00, "신뢰": 0.00, "공포": 0.00, "놀람": 0.00,
    "슬픔": 0.00, "혐오": 0.00, "분노": 0.00, "기대": 0.00
  },
  "PAD": {"P": 0.00, "A": 0.00, "D": 0.00},
  "emotion_target": {
    "source": "감정을 유발한 원인 (7가지 범주 중 하나)",
    "direction": "감정이 향하는 방향 (7가지 범주 중 하나)"
  },
  "combinated_emotion": "플루치크 규칙에 따른 조합감정명 (예: 경멸, 적대감 등)",
  "complex_emotion": "PAD 맥락까지 종합한 최종 복합감정명",
  "rationale": "모든 점수와 감정명을 종합한 최종 분석 근거"
}',

  # 배치 전용 JSON 출력 지시 (기본 프롬프트에 추가됨)
  batch_json_instruction = '

## 중요: 응답은 반드시 유효한 JSON 형식으로만 출력하세요. 마크다운이나 다른 텍스트 없이 JSON만 출력하세요.',
  
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
  model_name = "2.5-flash-lite",  # gemini.R 패키지 호환 모델
  temperature = 0.25,
  top_p = 0.85,
  rate_limit_per_minute = 3900,
  wait_time_seconds = 1,
  max_retries = 5
)

# 테스트 설정  
TEST_CONFIG <- list(
  model_name = "2.5-flash-lite",  # gemini.R 패키지 호환 모델
  temperature = 0.25,
  top_p = 0.85,
  max_retries = 3
)

# 배치 처리 설정
BATCH_CONFIG <- list(
  # 모델 및 API 설정
  model_name = "gemini-2.5-flash-lite",                # 배치 모드 지원 모델
  temperature = 0.25,                        # 온도 설정
  top_p = 0.85,                             # Top-p 설정
  #max_output_tokens = 2048,                 # 최대 출력 토큰
  
  # 배치 제한 설정 (서버 안정성 최적화)
  max_batch_size = 10000,                   # 배치당 최대 요청 수 (서버 과부하 방지)
  optimal_batch_size = 1000,                # 최적 배치 크기 (빠른 처리)
  max_file_size_mb = 500,                   # 최대 파일 크기 (500MB, 안정성 향상)
  
  # 적응형 배치 크기 설정
  enable_adaptive_batching = TRUE,           # 적응형 배치 크기 활성화
  batch_size_on_error = 500,                # 오류 발생 시 축소된 배치 크기
  split_large_batches = TRUE,               # 대용량 배치 자동 분할
  
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
  source_data = "data/data_collection.csv",  # 원본 CSV는 유지 (입력 전용)
  prompts_data = "data/prompts_ready",  # 확장자 없이 (자동 감지)
  functions_file = "libs/functions.R",
  checkpoints_dir = "checkpoints",
  human_coding_dir = "human_coding"
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

# =============================================================================
# JSON 스키마 설정 (중앙 관리)
# =============================================================================
EMOTION_SCHEMA <- list(
  type = "OBJECT",
  properties = list(
    plutchik_emotions = list(type = "OBJECT", properties = list(
      "기쁨" = list(type = "NUMBER", minimum = 0, maximum = 1), "신뢰" = list(type = "NUMBER", minimum = 0, maximum = 1),
      "공포" = list(type = "NUMBER", minimum = 0, maximum = 1), "놀람" = list(type = "NUMBER", minimum = 0, maximum = 1),
      "슬픔" = list(type = "NUMBER", minimum = 0, maximum = 1), "혐오" = list(type = "NUMBER", minimum = 0, maximum = 1),
      "분노" = list(type = "NUMBER", minimum = 0, maximum = 1), "기대" = list(type = "NUMBER", minimum = 0, maximum = 1)
    ), required = c("기쁨", "신뢰", "공포", "놀람", "슬픔", "혐오", "분노", "기대")),
    PAD = list(type = "OBJECT", properties = list(
      P = list(type = "NUMBER", minimum = -1, maximum = 1), A = list(type = "NUMBER", minimum = -1, maximum = 1), D = list(type = "NUMBER", minimum = -1, maximum = 1)
    ), required = c("P", "A", "D")),
    emotion_target = list(type = "OBJECT", properties = list(
      source = list(type = "STRING"),
      direction = list(type = "STRING")
    ), required = c("source", "direction")),
    combinated_emotion = list(type = "STRING"),
    complex_emotion = list(type = "STRING"),
    rationale = list(type = "STRING")
  ),
  required = c("plutchik_emotions", "PAD", "emotion_target", "combinated_emotion", "complex_emotion", "rationale")
)