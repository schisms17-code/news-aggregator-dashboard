
# ============================================================
# NEWS AGGREGATOR 3.0
# AUTOMATED CLOUD PUBLISHING RUNNER
# File: R/05_run_cloud_publish.R
# ============================================================

project_dir <- paste0(
  "C:/Users/vonne/OneDrive/Desktop/",
  "news_aggregator"
)

setwd(project_dir)

log_dir <- file.path(project_dir, "logs", "publishing")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(
  log_dir,
  paste0(
    "publish_",
    format(Sys.time(), "%Y%m%d_%H%M%S"),
    ".log"
  )
)

publish_lock <- file.path(log_dir, ".publish_lock")

if (!dir.create(publish_lock, showWarnings = FALSE)) {
  stop("Another publishing process may be running")
}

tryCatch({

  cat("Publishing started:", as.character(Sys.time()), "\n")

  source("R/04_publish_news_dashboard.R")

  publish_news_dashboard(deploy = TRUE)

  cat("Publishing completed:", as.character(Sys.time()), "\n")

  writeLines(
    c(
      "Status: SUCCESS",
      paste("Time:", Sys.time()),
      "Application: news-aggregator-dashboard"
    ),
    log_file
  )

}, error = function(e) {

  writeLines(
    c(
      "Status: FAILED",
      paste("Time:", Sys.time()),
      paste("Error:", conditionMessage(e))
    ),
    log_file
  )

  message("CLOUD PUBLISHING FAILED: ", conditionMessage(e))

  quit(save = "no", status = 1L)

}, finally = {

  unlink(publish_lock, recursive = TRUE, force = TRUE)

})
