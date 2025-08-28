# 개선된 06 배치 모니터 테스트
setwd('C:/Users/rubat/SynologyDrive/R_project/emotion-analysis-indischool')
source('libs/config.R')
source('06_batch_monitor.R')

# 개선된 BatchMonitor로 사용자가 지정한 배치 결과 재처리 테스트
batch_manager <- BatchMonitor$new()
batch_id <- 'batches/v54vae0nhoe5tmep1fqiiq1zoi7f62mxl8b0'

cat('=== 개선된 배치 모니터 테스트 ===\n')
cat('배치 ID:', batch_id, '\n')

tryCatch({
  result <- batch_manager$process_completed_batch(batch_id)
  if (!is.null(result)) {
    cat('✅ 배치 결과 처리 성공!\n')
    cat('처리된 행 수:', nrow(result), '\n')
    cat('컬럼 수:', ncol(result), '\n')
    
    # 핵심 컬럼 확인
    essential_cols <- c('post_id', 'comment_id', '기쁨', '신뢰', 'combinated_emotion', 'complex_emotion')
    missing <- setdiff(essential_cols, names(result))
    if (length(missing) == 0) {
      cat('✅ 핵심 컬럼 모두 포함됨\n')
    } else {
      cat('❌ 누락 컬럼:', paste(missing, collapse=', '), '\n')
    }
    
    # 첫 번째 결과 샘플
    if (nrow(result) > 0) {
      cat('\n첫 번째 결과 샘플:\n')
      cat('Post ID:', result$post_id[1], '\n')
      cat('Comment ID:', result$comment_id[1], '\n')
      if ('combinated_emotion' %in% names(result)) {
        cat('조합감정:', result$combinated_emotion[1], '\n')
      }
      if ('complex_emotion' %in% names(result)) {
        cat('복합감정:', result$complex_emotion[1], '\n')
      }
    }
  } else {
    cat('❌ 배치 결과 처리 실패\n')
  }
}, error = function(e) {
  cat('❌ 오류 발생:', e$message, '\n')
  cat('상세 오류:\n')
  print(e)
})