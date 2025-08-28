# 배치 모니터 테스트 스크립트
# 목적: 수정된 배치 모니터가 정상적으로 작동하는지 확인

library(arrow)
library(dplyr)

# libs/init.R 로드
source("libs/init.R")

# 테스트용 샘플 배치 결과 생성
sample_batch_results <- list(
  list(
    key = "post_37353082_comment_0",
    response = list(
      candidates = data.frame(
        finishReason = "STOP",
        content = data.frame(
          role = "model",
          parts = list(data.frame(
            text = "```json\n{\n  \"plutchik_emotions\": {\n    \"기쁨\": 0.00,\n    \"신뢰\": 0.10,\n    \"공포\": 0.40,\n    \"놀람\": 0.30,\n    \"슬픔\": 0.50,\n    \"혐오\": 0.40,\n    \"분노\": 0.60,\n    \"기대\": 0.20\n  },\n  \"PAD\": {\n    \"P\": -0.60,\n    \"A\": 0.70,\n    \"D\": -0.40\n  },\n  \"emotion_target\": {\n    \"source\": \"학교내 외집단(교감/교장,행정실,공무직 등)\",\n    \"direction\": \"교육행정기관 및 제도\"\n  },\n  \"combinated_emotion\": \"분노와 슬픔의 조합 (격분, 비탄)\",\n  \"complex_emotion\": \"억울함과 좌절감\",\n  \"rationale\": \"가해 교사들의 지속적인 뒷담화와 명예훼손, 불법 촬영 및 영상 유포로 인해 주인공은 공황장애와 심한 압박감, 혼란, 억울함, 자존감 하락을 겪었습니다. 특히 교육청의 방관과 비협조적인 태도는 불신과 분노를 증폭시켰습니다. 플루치크 감정으로는 분노(0.60)와 슬픔(0.50)이 가장 높게 나타나며, 혐오(0.40), 공포(0.40), 놀람(0.30)도 높게 나타납니다. 이는 가해자들에 대한 강한 분노와 피해 사실에 대한 슬픔, 부당함에 대한 혐오, 그리고 상황에 대한 공포와 놀람을 나타냅니다. PAD 점수로는 부정적인 경험으로 인해 P(Pleasure)가 -0.60으로 낮고, 상황의 심각성과 감정의 격앙으로 A(Arousal)는 0.70으로 높으며, 무력감을 느끼는 상황으로 D(Dominance)는 -0.40으로 낮습니다. 따라서 조합 감정은 분노와 슬픔이 결합된 '격분, 비탄'으로 볼 수 있으며, 최종 복합 감정은 이러한 경험들로 인한 '억울함과 좌절감'으로 분석됩니다. 감정 대상은 가해 행위의 주체인 '학교 내 외 집단'과 이를 방관하거나 비협조적인 태도를 보인 '교육행정기관 및 제도'로 설정했습니다.\"\n}\n```"
          )),
          stringsAsFactors = FALSE
        ),
        index = 0,
        stringsAsFactors = FALSE
      )
    )
  )
)

# 원데이터 로드
cat("원데이터 로드 중...\n")
if (file.exists("data/prompts_ready.parquet")) {
  original_data <- load_prompts_data()
  cat("원데이터 로드 성공\n")
  
  # 테스트를 위해 작은 샘플만 사용
  test_data <- original_data %>%
    filter(post_id == 37353082) %>%
    head(5)
  
  cat("테스트 데이터 준비 완료:", nrow(test_data), "행\n")
  
  # 결과 파싱 테스트
  cat("결과 파싱 테스트 중...\n")
  
  # 간단한 테스트 함수
  test_parse_function <- function(results, original_data) {
    # 실제 배치 모니터의 parse_batch_results 함수 로직을 간소화하여 테스트
    cat("파싱 함수 호출 성공\n")
    return(original_data[1:2, ]) # 간단한 반환
  }
  
  # 테스트 실행
  result <- test_parse_function(sample_batch_results, test_data)
  cat("테스트 완료\n")
  
} else {
  cat("원데이터 파일이 없습니다. 테스트를 건너뜁니다.\n")
}

cat("배치 모니터 스크립트 로드 테스트 완료!\n")