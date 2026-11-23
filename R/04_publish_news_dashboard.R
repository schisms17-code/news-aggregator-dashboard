
# ============================================================
# NEWS AGGREGATOR 3.0 — CLOUD PUBLISHING
# File: R/04_publish_news_dashboard.R
# ============================================================

publish_news_dashboard <- function(
    project_dir = "C:/Users/vonne/OneDrive/Desktop/news_aggregator",
    deploy = FALSE
) {

  project_dir <- normalizePath(
    project_dir,
    winslash = "/",
    mustWork = TRUE
  )

  deploy_dir <- file.path(
    project_dir, "deployment", "news-aggregator"
  )

  source_dir <- file.path(
    project_dir, "data", "processed"
  )

  target_dir <- file.path(
    deploy_dir, "data", "processed"
  )

  if (!file.exists(file.path(deploy_dir, "app.R"))) {
    stop("Deployment application not found")
  }

  dir.create(
    target_dir,
    recursive = TRUE,
    showWarnings = FALSE
  )

  files <- c(
    "news_articles_latest.rds",
    "news_articles_archive.rds"
  )

  # Validate all source data before copying.
  for (filename in files) {

    source_file <- file.path(source_dir, filename)

    if (!file.exists(source_file)) {
      stop("Missing source dataset: ", source_file)
    }

    dataset <- readRDS(source_file)

    if (!is.data.frame(dataset) || nrow(dataset) == 0L) {
      stop("Invalid or empty dataset: ", filename)
    }

    cat(
      "Validated:", filename,
      "| Articles:", nrow(dataset), "\n"
    )
  }

  # Copy the validated datasets.
  for (filename in files) {

    copied <- file.copy(
      from = file.path(source_dir, filename),
      to = file.path(target_dir, filename),
      overwrite = TRUE
    )

    if (!copied) {
      stop("Failed to copy: ", filename)
    }

    cat("Updated deployment file:", filename, "\n")
  }

  cat("\nDeployment data synchronized.\n")

  if (!deploy) {
    cat("DRY RUN: No cloud deployment requested.\n")
    return(invisible(TRUE))
  }

  if (!requireNamespace("rsconnect", quietly = TRUE)) {
    stop("rsconnect is not installed")
  }

  cat("\nPublishing to shinyapps.io...\n")

  rsconnect::deployApp(
    appDir = deploy_dir,
    appName = "news-aggregator-dashboard",
    appTitle = "News Intelligence Aggregator 3.0",
    account = "hydrocodex",
    server = "shinyapps.io",
    launch.browser = FALSE
  )

  cat("\nCLOUD PUBLISHING COMPLETE\n")

  invisible(TRUE)
}
