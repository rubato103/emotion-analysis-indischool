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
  base_instructions = '## ROLE: Research Assistant
## TARGET: Elementary School Teacher Community Text (Korean)

## INSTRUCTIONS:
1.  Score emotions based on underlying motives, not just surface-level text.
2.  Final Review: After writing the rationale, you MUST adjust the scores and emotion_target classifications to ensure they are logically consistent with your final reasoning.

4.  **Score Plutchik"s 8 Basic Emotions (0.00-1.00)**:
    * Joy(기쁨)↔Sadness(슬픔): Serenity → Joy → Ecstasy | satisfaction, pleasure, delight, happiness
    * Trust(신뢰)↔Disgust(혐오): Acceptance → Trust → Admiration | belief, reliance, respect, attachment
    * Fear(공포)↔Anger(분노): Apprehension → Fear → Terror | anxiety, worry, caution, withdrawal
    * Surprise(놀람)↔Anticipation(기대): Distraction → Surprise → Amazement | astonishment, shock, confusion
    * Sadness(슬픔)↔Joy(기쁨): Pensiveness → Sadness → Grief | disappointment, loss, despair
    * Disgust(혐오)↔Trust(신뢰): Boredom → Disgust → Loathing | rejection, contempt, aversion
    * Anger(분노)↔Fear(공포): Annoyance → Anger → Rage | fury, resentment, hostility, outrage
    * Anticipation(기대)↔Surprise(놀람): Interest → Anticipation → Vigilance | curiosity, preparation, planningJoy(기쁨)↔Sadness(슬픔), Trust(신뢰)↔Disgust(혐오), Fear(공포)↔Anger(분노), Surprise(놀람)↔Anticipation(기대)

5.  **Apply Plutchik"s Combination Rules**:
    * **Emotion Wheel Sequence**: 기쁨 → 신뢰 → 공포 → 놀람 → 슬픔 → 혐오 → 분노 → 기대 → (cycle)
    5-1.  Find the Primary Dyad (adjacent emotions) with the highest combined scores first. Name the combinated_emotion based on this dyad.
      * Examples: 기쁨+신뢰=사랑(Love), 신뢰+공포=복종(Submission), 분노+기대=공격성(Aggressiveness), 기쁨+분노=질투(Jealousy)
    5-2.  If no strong primary dyad exists, describe the emotional state in combinated_emotion (e.g., 분노와 슬픔의 공존).
      * Use of Other Combinations: Use secondary dyads (one apart) and opposites to explain psychological complexity within the rationale, but not for naming the combinated_emotion unless they are the dominant emotional theme.

6.  **Score PAD Model (-1.00~1.00)**:
    * P(Pleasure)
    * A(Arousal): The intensity or energy level of the emotion.
    * D(Dominance): The sense of control or influence over the situation/others.
      Closer to +1.0 when the speaker feels in control, empowered, influential, or is taking initiative (e.g., offering a solution, making a strong assertion).
      Closer to -1.0 when the speaker feels controlled, helpless, submissive, or victimized by external factors (e.g., policies, other people).

7.  **Name `combinated_emotion`**: Name the emotion based on the combination rules.

8.  **Name `complex_emotion`**: Name the final complex emotion by synthesizing the `combinated_emotion` and the PAD scores.

9.  **Provide Rationale**: For the rationale field, write a concise, qualitative narrative. Explain the reasoning for the complex_emotion by connecting it to specific nuances and quotes in the text. Do not repeat numerical scores or classification paths from other fields, as this information is already structured.

## CAUTIONS:
* Grounded Inference: All reasoning must originate from the text. Use broader context (e.g., the original post, teacher community norms) only to interpret ambiguous phrases or to deepen the understanding of stated facts. Context should not be used to invent targets or causes that have no textual basis. The text provides the "what" and "who"; the context informs the "why" and "how intensely"
* Name complex emotions based on 2-3 strong emotions (score > 0.3).
* **교사 커뮤니티 맥락 반영 (Reflect the context of the Korean teacher community).**
* Prioritize simple, intuitive interpretations for short texts.
* Consider complex emotional combinations for long texts.
* Beware of irony and sarcasm.

'
,

  # 공통 JSON 구조 정의 (확장된 버전)
    json_structure = '## JSON Response Structure:
{
  "plutchik_emotions": {
    "기쁨": 0.00, "신뢰": 0.00, "공포": 0.00, "놀람": 0.00,
    "슬픔": 0.00, "혐오": 0.00, "분노": 0.00, "기대": 0.00
  },
  "PAD": {
    "P": 0.00, 
    "A": 0.00, 
    "D": 0.00
  },
  "emotion_target": {
    "source": {
      "major": "Major category of the emotion`s cause",
      "middle": "Middle category of the emotion`s cause",
      "minor": "Minor category of the emotion`s cause (if applicable)"
    },
    "direction": {
      "major": "Major category of the emotion`s target",
      "middle": "Middle category of the emotion`s target",
      "minor": "Minor category of the emotion`s target (if applicable)"
    }
  },
  "combinated_emotion": "Name of combined emotion based on Plutchik`s rules (e.g., 경멸, 적대감)",
  "complex_emotion": "Final complex emotion name, synthesizing with PAD context",
  "rationale": "Comprehensive reasoning for all scores and emotion names based on the text"
}

## IMPORTANT OUTPUT INSTRUCTION:
1. The final output must be a valid JSON object that **strictly adheres to the requested structure**.
2. All keys and string values within this JSON must be entirely in **KOREAN (한국어)**.
',

  # 배치 전용 JSON 출력 지시 (기본 프롬프트에 추가됨)
  batch_json_instruction = '',
  
  
  # 댓글 분석용 작업 지시
  comment_task = "## TASK: Considering the context of the 'Original Post', analyze the emotion of the following 'Comment to Analyze'.
3.  **Emotion Target Classification**: Structure the `source`(cause) and `direction`(target) as separate JSON objects, each with `major`, `middle`, and `minor` keys. **For example: `'source': {'major': '1. 학교 내부', 'middle': '1-3. 교직원', 'minor': '동료 교사'}`.**

    * **[General Classification Principles (Apply to ALL text)]**
        * **Direct Cause Priority**: When classifying the source, you must identify the actor or event that directly prompted the user to write the text. This is often the subject of the immediate action being discussed (e.g., a person's statement, a union's action), not the broader background problem.
            * Example 1 (State vs. Trigger): For the text 'My colleague pushed all their work onto me, so I got burnout,' the source is 1-3. 교직원 - 동료 교사 (the colleague's action), not 1-5. 교사 개인 - 번아웃/정서적 소진 (the resulting state).
            * Example 2 (Actor vs. Topic): For a comment criticizing a specific teacher's union like 'Jeongyojo can't even unify 40,000 members,' the source is 2-3. 사회/외부 - 교원 단체 (the specific actor), not 3-2. 정보/담론 (the general topic).
        * **Specificity Priority**: Always classify to the most specific '소분류' (minor category). Use '중분류' (middle category) only if a minor category is not applicable.
        * **Source/Direction Separation**: The source (cause) and direction (target) can be different. The direction is the final target where the emotion is expressed or psychologically projected. (e.g., Anger caused by a frustrating 'policy' (source) might be projected onto a more accessible 'manager' (direction)).
        * **Minimize 'Other'**: Use the '3. 기타' (Other) category only for exceptional cases. If used, specify the reason in the `rationale`.

    * **[Additional Principles for Comments ONLY (댓글 분석 시 추가 원칙)]**
        * When analyzing a comment, the Original Post (OP) and its author are key context.
        * **For the `source`**: If the comment reacts to the **OP’s content/idea**, the `source` is often `3-2. 정보/담론`. If it reacts to the **author`s action** of posting, the `source` is often `1-3. 교직원 - 동료 교사`.
        * **For the `direction`**: If the emotion is aimed **at the author**, the `direction` is `1-3. 교직원 - 동료 교사`. If the emotion **is shared with the author towards a third party**, the `direction` is that third party.

    * **[KOREAN Classification System]**
        * **1. 학교 내부 (Internal to School)**
            * **1-1. 학생 (Student)**: (소분류: 생활지도/문제행동(Guidance/Behavioral Issues), 학습/수업 태도(Learning/Class Attitude), 교우/사제 관계(Peer/Teacher Relations))
            * **1-2. 학부모 (Parent)**: (소분류: 소통/상담(Communication/Counseling), 민원/갈등(Complaints/Conflict), 교육 참여/요구(Involvement/Demands))
            * **1-3. 교직원 (School Staff)**: (소분류: 관리자(Supervisor/Superior), 동료 교사(Colleague), 기타 직원(Other Staff))
            * **1-4. 교육 활동 (Educational Activities)**: (소분류: 교과/수업(Curriculum/Class), 행정 업무(Administrative Work), 학교 행사/활동(School Events))
            * **1-5. 교사 개인 (Teacher - Personal)**: (소분류: 전문성/효능감(Professionalism/Efficacy), 번아웃/정서적 소진(Burnout/Emotional Exhaustion), 워라밸/복무(Work-Life Balance/Duty))
        * **2. 학교 외부 (External to School)**
            * **2-1. 교육 당국 (Education Authorities)**: (소분류: 교육부(Ministry of Education), 교육청(Office of Education))
            * **2-2. 제도/정책 (System/Policy)**: (소분류: 법률(Law), 행정 정책(Administrative Policy), 인사/평가 제도(HR/Evaluation System))
            * **2-3. 사회/외부 (Society/External)**: (소분류: 언론/미디어(Media), 정치권(Politics), 관련 기관(Related Organizations), 교원 단체(Teacher Union/Group))
        * **3. 기타 (Etc.)**
            * **3-1. 특정 사건/이슈 (Specific Incident/Issue)**: (소분류: 교육계 주요 사건(Major Educational Event), 커뮤니티 내 논쟁(Community Debate))
            * **3-2. 정보/담론 (Information/Discourse)**: (소분류: 불특정 다수 비난(Public Criticism), 특정 뉴스/콘텐츠(Specific News/Content))",
  
  # 게시글 분석용 작업 지시  
  post_task = "## TASK: Analyze the emotion of the following 'Post'.
  3.  **Emotion Target Classification**: Structure the `source`(cause) and `direction`(target) as separate JSON objects, each with `major`, `middle`, and `minor` keys. **For example: `'source': {'major': '1. 학교 내부', 'middle': '1-3. 교직원', 'minor': '동료 교사'}`.**

    * **[General Classification Principles]**
        * **Direct Cause Priority**: When classifying the source, you must identify the actor or event that directly prompted the user to write the text. This is often the subject of the immediate action being discussed (e.g., a person's statement, a union's action), not the broader background problem.
            * Example 1 (State vs. Trigger): For the text 'My colleague pushed all their work onto me, so I got burnout,' the source is 1-3. 교직원 - 동료 교사 (the colleague's action), not 1-5. 교사 개인 - 번아웃/정서적 소진 (the resulting state).
            * Example 2 (Actor vs. Topic): For a comment criticizing a specific teacher's union like 'Jeongyojo can't even unify 40,000 members,' the source is 2-3. 사회/외부 - 교원 단체 (the specific actor), not 3-2. 정보/담론 (the general topic).
        * **Specificity Priority**: Always classify to the most specific '소분류' (minor category). Use '중분류' (middle category) only if a minor category is not applicable.
        * **Source/Direction Separation**: The source (cause) and direction (target) can be different. The direction is the final target where the emotion is expressed or psychologically projected. (e.g., Anger caused by a frustrating 'policy' (source) might be projected onto a more accessible 'manager' (direction)).

    * **[KOREAN Classification System]**
        * **1. 학교 내부 (Internal to School)**
            * **1-1. 학생 (Student)**: (소분류: 생활지도/문제행동(Guidance/Behavioral Issues), 학습/수업 태도(Learning/Class Attitude), 교우/사제 관계(Peer/Teacher Relations))
            * **1-2. 학부모 (Parent)**: (소분류: 소통/상담(Communication/Counseling), 민원/갈등(Complaints/Conflict), 교육 참여/요구(Involvement/Demands))
            * **1-3. 교직원 (School Staff)**: (소분류: 관리자(Supervisor/Superior), 동료 교사(Colleague), 기타 직원(Other Staff))
            * **1-4. 교육 활동 (Educational Activities)**: (소분류: 교과/수업(Curriculum/Class), 행정 업무(Administrative Work), 학교 행사/활동(School Events))
            * **1-5. 교사 개인 (Teacher - Personal)**: (소분류: 전문성/효능감(Professionalism/Efficacy), 번아웃/정서적 소진(Burnout/Emotional Exhaustion), 워라밸/복무(Work-Life Balance/Duty))
        * **2. 학교 외부 (External to School)**
            * **2-1. 교육 당국 (Education Authorities)**: (소분류: 교육부(Ministry of Education), 교육청(Office of Education))
            * **2-2. 제도/정책 (System/Policy)**: (소분류: 법률(Law), 행정 정책(Administrative Policy), 인사/평가 제도(HR/Evaluation System))
            * **2-3. 사회/외부 (Society/External)**: (소분류: 언론/미디어(Media), 정치권(Politics), 관련 기관(Related Organizations), 교원 단체(Teacher Union/Group))
        * **3. 기타 (Etc.)**
            * **3-1. 특정 사건/이슈 (Specific Incident/Issue)**: (소분류: 교육계 주요 사건(Major Educational Event), 커뮤니티 내 논쟁(Community Debate))
            * **3-2. 정보/담론 (Information/Discourse)**: (소분류: 불특정 다수 비난(Public Criticism), 특정 뉴스/콘텐츠(Specific News/Content))",
  
  # 섹션 헤더
  context_header = "# ORIGINAL POST (Context)",
  comment_header = "# COMMENT TO ANALYZE (Target)",
  post_header = "# POST TO ANALYZE (Target)"
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
      source = list(type = "OBJECT", properties = list(
        major = list(type = "STRING"),
        middle = list(type = "STRING"),
        minor = list(type = "STRING")
      ), required = c("major", "middle")),
      direction = list(type = "OBJECT", properties = list(
        major = list(type = "STRING"),
        middle = list(type = "STRING"),
        minor = list(type = "STRING")
      ), required = c("major", "middle"))
t(type = "STRING")
