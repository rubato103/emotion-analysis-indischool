# 실패 복구 시스템
# 체크포인트 기반 단계별 복구 메커니즘

# 체크포인트 관리 클래스
CheckpointManager <- R6::R6Class("CheckpointManager",
  public = list(
    script_name = NULL,
    checkpoint_dir = "checkpoints",
    
    initialize = function(script_name) {
      self$script_name <- script_name
      if (!dir.exists(self$checkpoint_dir)) {
        dir.create(self$checkpoint_dir, recursive = TRUE)
      }
    },
    
    # 체크포인트 저장
    save_checkpoint = function(data, step_name, metadata = NULL) {
      checkpoint_file <- file.path(
        self$checkpoint_dir, 
        sprintf("%s_%s_%s.RDS", self$script_name, step_name, Sys.Date())
      )
      
      checkpoint_data <- list(
        data = data,
        timestamp = Sys.time(),
        step_name = step_name,
        script_name = self$script_name,
        metadata = metadata,
        r_version = R.version.string,
        session_info = sessionInfo()
      )
      
      saveRDS(checkpoint_data, checkpoint_file)
      log_message("INFO", sprintf("체크포인트 저장: %s (%d행)", checkpoint_file, nrow(data)))
      
      return(checkpoint_file)
    },
    
    # 체크포인트 로드
    load_checkpoint = function(step_name, max_age_hours = 24) {
      pattern <- sprintf("%s_%s_.*\\.RDS", self$script_name, step_name)
      checkpoint_files <- list.files(self$checkpoint_dir, pattern = pattern, full.names = TRUE)
      
      if (length(checkpoint_files) == 0) {
        log_message("INFO", sprintf("'%s' 단계의 체크포인트가 없습니다.", step_name))
        return(NULL)
      }
      
      # 가장 최근 파일 선택
      latest_file <- checkpoint_files[which.max(file.mtime(checkpoint_files))]
      
      # 파일 나이 검증
      file_age <- difftime(Sys.time(), file.mtime(latest_file), units = "hours")
      if (as.numeric(file_age) > max_age_hours) {
        log_message("WARN", sprintf("체크포인트가 %d시간 이상 오래되었습니다: %s", 
                                   round(file_age, 1), latest_file))
        response <- readline("오래된 체크포인트를 사용하시겠습니까? (y/n): ")
        if (tolower(response) != "y") {
          return(NULL)
        }
      }
      
      checkpoint_data <- readRDS(latest_file)
      log_message("INFO", sprintf("체크포인트 로드: %s (저장시간: %s)", 
                                 latest_file, checkpoint_data$timestamp))
      
      return(checkpoint_data$data)
    },
    
    # 체크포인트 목록 조회
    list_checkpoints = function() {
      pattern <- sprintf("%s_.*\\.RDS", self$script_name)
      checkpoint_files <- list.files(self$checkpoint_dir, pattern = pattern, full.names = TRUE)
      
      if (length(checkpoint_files) == 0) {
        log_message("INFO", "저장된 체크포인트가 없습니다.")
        return(data.frame())
      }
      
      checkpoint_info <- data.frame(
        file = basename(checkpoint_files),
        path = checkpoint_files,
        size_mb = round(file.size(checkpoint_files) / 1024 / 1024, 2),
        modified = file.mtime(checkpoint_files),
        stringsAsFactors = FALSE
      )
      
      return(checkpoint_info)
    },
    
    # 오래된 체크포인트 정리
    cleanup_old_checkpoints = function(keep_days = 7) {
      pattern <- sprintf("%s_.*\\.RDS", self$script_name)
      checkpoint_files <- list.files(self$checkpoint_dir, pattern = pattern, full.names = TRUE)
      
      cutoff_date <- Sys.time() - (keep_days * 24 * 60 * 60)
      old_files <- checkpoint_files[file.mtime(checkpoint_files) < cutoff_date]
      
      if (length(old_files) > 0) {
        file.remove(old_files)
        log_message("INFO", sprintf("%d개의 오래된 체크포인트 파일을 삭제했습니다.", length(old_files)))
      }
    }
  )
)

# 실패 복구 래퍼 함수
with_recovery <- function(step_name, script_name, recovery_function, force_rerun = FALSE) {
  checkpoint_manager <- CheckpointManager$new(script_name)
  
  # 강제 재실행이 아니라면 체크포인트 확인
  if (!force_rerun) {
    cached_result <- checkpoint_manager$load_checkpoint(step_name)
    if (!is.null(cached_result)) {
      log_message("INFO", sprintf("'%s' 단계의 캐시된 결과를 사용합니다.", step_name))
      return(cached_result)
    }
  }
  
  # 실제 작업 실행
  log_message("INFO", sprintf("'%s' 단계를 실행합니다...", step_name))
  start_time <- Sys.time()
  
  result <- tryCatch({
    recovery_function()
  }, error = function(e) {
    log_message("ERROR", sprintf("'%s' 단계 실행 중 오류 발생: %s", step_name, e$message))
    
    # 부분적 결과가 있는지 확인
    partial_result <- try(recovery_function(partial = TRUE), silent = TRUE)
    if (!inherits(partial_result, "try-error")) {
      log_message("INFO", "부분적 결과를 체크포인트로 저장합니다.")
      checkpoint_manager$save_checkpoint(partial_result, paste0(step_name, "_partial"))
    }
    
    stop(e)
  })
  
  execution_time <- difftime(Sys.time(), start_time, units = "mins")
  
  # 성공한 결과를 체크포인트로 저장
  if (!is.null(result)) {
    metadata <- list(
      execution_time_mins = round(as.numeric(execution_time), 2),
      success = TRUE
    )
    checkpoint_manager$save_checkpoint(result, step_name, metadata)
    log_message("INFO", sprintf("'%s' 단계 완료 (소요시간: %.1f분)", step_name, execution_time))
  }
  
  return(result)
}

# 배치 처리 복구 함수
process_with_batch_recovery <- function(data, process_function, batch_size = 100, 
                                       checkpoint_name, script_name) {
  
  checkpoint_manager <- CheckpointManager$new(script_name)
  
  # 기존 진행상황 확인
  progress_file <- file.path(checkpoint_manager$checkpoint_dir, 
                            sprintf("%s_%s_progress.RDS", script_name, checkpoint_name))
  
  if (file.exists(progress_file)) {
    progress_info <- readRDS(progress_file)
    completed_batches <- progress_info$completed_batches
    results_so_far <- progress_info$results
    start_batch <- max(completed_batches) + 1
    
    log_message("INFO", sprintf("이전 진행상황에서 재시작: 배치 %d부터 (총 %d개 완료)", 
                               start_batch, length(completed_batches)))
  } else {
    completed_batches <- integer(0)
    results_so_far <- list()
    start_batch <- 1
  }
  
  # 배치 분할
  total_rows <- nrow(data)
  num_batches <- ceiling(total_rows / batch_size)
  
  log_message("INFO", sprintf("총 %d행을 %d개 배치로 처리 (배치 크기: %d)", 
                             total_rows, num_batches, batch_size))
  
  for (batch_num in start_batch:num_batches) {
    start_row <- (batch_num - 1) * batch_size + 1
    end_row <- min(batch_num * batch_size, total_rows)
    batch_data <- data[start_row:end_row, ]
    
    log_message("INFO", sprintf("배치 %d/%d 처리 중 (행 %d-%d)", 
                               batch_num, num_batches, start_row, end_row))
    
    tryCatch({
      batch_result <- process_function(batch_data)
      results_so_far[[batch_num]] <- batch_result
      completed_batches <- c(completed_batches, batch_num)
      
      # 진행상황 저장
      progress_info <- list(
        completed_batches = completed_batches,
        results = results_so_far,
        last_update = Sys.time()
      )
      saveRDS(progress_info, progress_file)
      
      log_message("INFO", sprintf("배치 %d/%d 완료", batch_num, num_batches))
      
    }, error = function(e) {
      log_message("ERROR", sprintf("배치 %d 처리 중 오류: %s", batch_num, e$message))
      log_message("INFO", "현재까지의 진행상황이 저장되었습니다. 나중에 재시작할 수 있습니다.")
      stop(sprintf("배치 %d에서 실패: %s", batch_num, e$message))
    })
  }
  
  # 최종 결과 병합
  final_result <- do.call(rbind, results_so_far)
  
  # 진행상황 파일 정리
  if (file.exists(progress_file)) {
    file.remove(progress_file)
  }
  
  log_message("INFO", sprintf("모든 배치 처리 완료: 총 %d행 처리", nrow(final_result)))
  return(final_result)
}