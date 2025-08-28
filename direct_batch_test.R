# 직접 API 호출 방식으로 개선된 배치 모니터 테스트
setwd('C:/Users/rubat/SynologyDrive/R_project/emotion-analysis-indischool')
source('libs/config.R')
source('06_batch_monitor.R')

cat('=== 개선된 배치 모니터 직접 API 테스트 ===\n')

# BatchMonitor 인스턴스 생성 (대화형 모드 비활성화)
batch_manager <- BatchMonitor$new()
batch_id <- 'batches/v54vae0nhoe5tmep1fqiiq1zoi7f62mxl8b0'

cat('배치 ID:', batch_id, '\n')

tryCatch({
  # 개선된 parse_batch_results 메소드 직접 테스트
  cat('\n1. JSONL 파일 직접 로드 테스트...\n')
  
  jsonl_file <- 'results/batch_raw_batch-v54vae0nhoe5tmep1fqiiq1zoi7f62mxl8b0_20250828_213949.jsonl'
  if (file.exists(jsonl_file)) {
    cat('✅ JSONL 파일 존재함:', jsonl_file, '\n')
    
    # 파일에서 결과 로드
    results <- batch_manager$load_saved_batch_results(file_path = jsonl_file)
    cat('✅ JSONL 파일 로드 성공! 결과 수:', length(results), '\n')
    
    if (length(results) > 0) {
      cat('\n2. 원데이터 로드 테스트...\n')
      
      # load_prompts_data() 함수 테스트
      tryCatch({
        original_data <- load_prompts_data()
        cat('✅ 원데이터 로드 성공:', nrow(original_data), '행\n')
        
        cat('\n3. 배치 결과 파싱 테스트...\n')
        
        # parse_batch_results 메소드 직접 호출
        parsed_results <- batch_manager$parse_batch_results(results, original_data)
        
        if (!is.null(parsed_results)) {
          cat('✅ 배치 결과 파싱 성공!\n')
          cat('처리된 행 수:', nrow(parsed_results), '\n')
          cat('컬럼 수:', ncol(parsed_results), '\n')
          
          # 핵심 컬럼 확인
          essential_cols <- c('post_id', 'comment_id', '기쁨', '신뢰', 'combinated_emotion', 'complex_emotion')
          missing <- setdiff(essential_cols, names(parsed_results))
          if (length(missing) == 0) {
            cat('✅ 핵심 컬럼 모두 포함됨\n')
            
            # 첫 번째 결과 샘플
            if (nrow(parsed_results) > 0) {
              cat('\n=== 첫 번째 결과 샘플 ===\n')
              cat('Post ID:', parsed_results$post_id[1], '\n')
              cat('Comment ID:', parsed_results$comment_id[1], '\n')
              cat('기쁨 점수:', parsed_results$기쁨[1], '\n')
              cat('신뢰 점수:', parsed_results$신뢰[1], '\n')
              cat('조합감정:', parsed_results$combinated_emotion[1], '\n')
              cat('복합감정:', parsed_results$complex_emotion[1], '\n')
              
              # Parquet 저장 테스트
              output_file <- 'results/test_improved_batch_result.parquet'
              tryCatch({
                arrow::write_parquet(parsed_results, output_file, compression = "snappy")
                cat('\n✅ Parquet 저장 성공:', output_file, '\n')
              }, error = function(e) {
                cat('\n❌ Parquet 저장 실패:', e$message, '\n')
              })
            }
          } else {
            cat('❌ 누락 컬럼:', paste(missing, collapse=', '), '\n')
          }
        } else {
          cat('❌ 배치 결과 파싱 실패\n')
        }
        
      }, error = function(e) {
        cat('❌ 원데이터 로드 오류:', e$message, '\n')
      })
    }
  } else {
    cat('❌ JSONL 파일을 찾을 수 없습니다:', jsonl_file, '\n')
  }
  
}, error = function(e) {
  cat('❌ 전체 프로세스 오류:', e$message, '\n')
  cat('상세 오류:\n')
  print(e)
})