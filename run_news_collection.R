# Retain only the newest historical archive repair backups.
# This function NEVER touches raw snapshots, logs, or the active archive.
cleanup_archive_backups <- function(project_dir, keep = 10L, dry_run = TRUE) {
  if (!is.character(project_dir) || length(project_dir) != 1L ||
      is.na(project_dir) || !dir.exists(project_dir)) {
    stop("A valid project directory is required")
  }
  if (length(keep) != 1L || is.na(keep) || !is.finite(keep) ||
      keep < 1 || keep != as.integer(keep)) {
    stop("keep must be a positive whole number")
  }
  backup_dir <- file.path(project_dir, "data", "processed")
  if (!dir.exists(backup_dir)) {
    cat("Backup directory not found; cleanup skipped.\n")
    return(invisible(character()))
  }
  # Exact filename pattern: no arbitrary RDS files will be considered.
  backups <- list.files(
    backup_dir,
    pattern = "^news_articles_archive_backup_[0-9]{8}_[0-9]{6}\\.rds$",
    full.names = TRUE
  )
  if (length(backups) <= keep) {
    cat("Archive backup retention:", length(backups),
        "backup(s); nothing to remove.\n")
    return(invisible(character()))
  }
  # Timestamp in filename is sortable; break ties by full path.
  backups <- sort(backups, decreasing = TRUE)
  obsolete <- backups[seq.int(keep + 1L, length(backups))]
  cat("Archive backup retention: keeping", keep, "of", length(backups),
      "backups;", length(obsolete), "older backup(s)",
      if (dry_run) "would be removed.\n" else "to remove.\n")
  for (path in obsolete) {
    cat(if (dry_run) "  WOULD DELETE: " else "  DELETE: ",
        basename(path), "\n", sep = "")
  }
  if (!dry_run) {
    removed <- file.remove(obsolete)
    if (any(!removed)) {
      warning("Could not delete ", sum(!removed), " old archive backup(s): ",
              paste(basename(obsolete[!removed]), collapse = ", "))
    }
  }
  invisible(obsolete)
}

# News Aggregator - scheduled collection wrapper
# Save in project root as run_news_collection.R

run_scheduled_collection <- function() {
  project_dir <- "C:/Users/vonne/OneDrive/Desktop/news_aggregator"
  if (!dir.exists(project_dir)) stop("Project folder not found: ", project_dir)
  setwd(project_dir)

  log_dir <- file.path(project_dir, "logs", "scheduler")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  lock_dir <- file.path(project_dir, "logs", ".collection_lock")

  if (!dir.create(lock_dir, showWarnings = FALSE)) {
    stop("Collection lock already exists. Verify no other collector is running: ", lock_dir)
  }
  on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)

  started <- Sys.time()
  log_file <- file.path(log_dir, paste0("collection_", format(started, "%Y%m%d_%H%M%S"), ".log"))
  log_con <- file(log_file, open = "wt")
  sink(log_con, split = TRUE)
  sink(log_con, type = "message")
  on.exit({
    sink(type = "message")
    sink()
    close(log_con)
  }, add = TRUE, after = FALSE)

  cat("Started:", format(started, "%Y-%m-%d %H:%M:%S %Z"), "\n")
  cat("Project:", project_dir, "\n")
  cat("Log:", log_file, "\n")

  script <- file.path(project_dir, "R", "01_collect_news.R")
  latest <- file.path(project_dir, "data", "processed", "news_articles_latest.rds")
  if (!file.exists(script)) stop("Collector script not found: ", script)
  previous_mtime <- if (file.exists(latest)) file.info(latest)$mtime else as.POSIXct(NA)

  collector_env <- new.env(parent = globalenv())
  source(script, local = collector_env, echo = FALSE)
  if (!exists("collect_all_news", envir = collector_env, mode = "function", inherits = FALSE)) {
    stop("collect_all_news() was not defined by ", script)
  }

  cat("Executing collect_all_news()...\n")
  results <- collector_env$collect_all_news()
  if (!is.list(results) || !all(c("articles", "feed_log") %in% names(results))) {
    stop("Collector returned an unexpected result; expected articles and feed_log.")
  }
  cat("Returned articles:", nrow(results$articles), "\n")
  cat("Returned feed log rows:", nrow(results$feed_log), "\n")
  if (is.data.frame(results$feed_log) && "status" %in% names(results$feed_log)) {
    print(table(results$feed_log$status, useNA = "ifany"))
  }
  if (!file.exists(latest)) stop("Expected output was not created: ", latest)
  new_mtime <- file.info(latest)$mtime
  if (is.na(new_mtime) || (!is.na(previous_mtime) && new_mtime <= previous_mtime)) {
    stop("Collector finished but the latest RDS timestamp did not advance: ", latest)
  }
  cat("Latest RDS updated:", format(new_mtime, "%Y-%m-%d %H:%M:%S %Z"), "\n")
  # Rebuild the historical archive only after the latest snapshot is saved.
  archive_script <- file.path(project_dir, "R", "02_build_news_archive.R")
  if (!file.exists(archive_script)) stop("Archive builder not found: ", archive_script)
  archive_env <- new.env(parent = globalenv())
  source(archive_script, local = archive_env, echo = FALSE)
  if (!exists("build_news_archive", envir = archive_env, mode = "function", inherits = FALSE)) {
    stop("Archive builder function was not defined")
  }
  cat("Rebuilding historical archive...\n")
  archive <- archive_env$build_news_archive(project_dir = project_dir)
  if (!is.data.frame(archive) || nrow(archive) == 0L) stop("Archive build returned no articles")
  cat("Historical archive unique articles:", nrow(archive), "\n")

  # Repair publication dates after rebuilding from historical snapshots.
  # The repair script preserves raw publication dates and backs up the archive.
  repair_script <- file.path(project_dir, "R", "03_repair_archive_dates.R")
  if (!file.exists(repair_script)) stop("Archive date repair script not found: ", repair_script)
  repair_env <- new.env(parent = globalenv())
  source(repair_script, local = repair_env, echo = FALSE)
  if (!exists("repair_archive_dates", envir = repair_env, mode = "function", inherits = FALSE)) {
    stop("repair_archive_dates() was not defined by ", repair_script)
  }
  cat("Repairing historical publication dates...\n")
  repaired_archive <- repair_env$repair_archive_dates()
  if (!is.data.frame(repaired_archive) || nrow(repaired_archive) != nrow(archive)) {
    stop("Date repair changed the historical article count unexpectedly")
  }
  if (!all(c("article_key", "publication_date_utc") %in% names(repaired_archive))) {
    stop("Repaired archive is missing required columns")
  }
  if (anyDuplicated(repaired_archive$article_key)) {
    stop("Repaired archive contains duplicate article keys")
  }
  missing_dates <- sum(is.na(repaired_archive$publication_date_utc))
  cat("Historical archive missing publication dates:", missing_dates, "\n")
  if (missing_dates > 0L) {
    warning("Historical archive still has ", missing_dates, " missing publication dates")
  }
  # Retention runs only after archive rebuilding and date repair finish.
  # A cleanup failure is logged but does not invalidate a successful collection.
  cat("Applying historical archive backup retention (keep 10)...\n")
  tryCatch(
    cleanup_archive_backups(project_dir, keep = 10L, dry_run = FALSE),
    error = function(e) warning("Backup retention skipped: ", conditionMessage(e))
  )
  cat("Finished:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n")
  cat("Collection succeeded.\n")
  invisible(results)
}

# Running via Rscript executes this wrapper. Sourcing it into an interactive
# RStudio session only defines the function; call it manually to test.
if (sys.nframe() == 0L) {
  tryCatch(
    run_scheduled_collection(),
    error = function(e) {
      message("SCHEDULED COLLECTION FAILED: ", conditionMessage(e))
      quit(save = "no", status = 1L)
    }
  )
}
