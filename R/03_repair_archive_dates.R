
# ============================================================
# NEWS AGGREGATOR
# 03_repair_archive_dates.R
# Recover historical RSS publication timestamps
# ============================================================

repair_archive_dates <- function() {

  archive_path <- file.path(
    "data", "processed", "news_articles_archive.rds"
  )

  csv_path <- file.path(
    "data", "processed", "news_articles_archive.csv"
  )

  if (!file.exists(archive_path)) {
    stop("Historical archive not found.")
  }

  archive <- readRDS(archive_path)

  required <- c(
    "publication_date_raw",
    "publication_date_utc"
  )

  if (!all(required %in% names(archive))) {
    stop("Archive is missing required date columns.")
  }

  # Create backup before changing anything
  backup_path <- file.path(
    "data", "processed",
    paste0(
      "news_articles_archive_backup_",
      format(Sys.time(), "%Y%m%d_%H%M%S"),
      ".rds"
    )
  )

  saveRDS(archive, backup_path)

  cat("Backup created:", backup_path, "\n")

  before <- sum(is.na(archive$publication_date_utc))

  missing_idx <- which(
    is.na(archive$publication_date_utc) &
      !is.na(archive$publication_date_raw) &
      nzchar(trimws(archive$publication_date_raw))
  )

  # Parse RFC 822-style GMT timestamps.
  # Use an English locale where available because
  # RSS timestamps contain English weekday/month names.
  original_locale <- Sys.getlocale("LC_TIME")

  on.exit(
    try(Sys.setlocale("LC_TIME", original_locale),
        silent = TRUE),
    add = TRUE
  )

  locale_set <- FALSE

  for (loc in c(
    "English_United States.1252",
    "en_US.UTF-8",
    "C"
  )) {
    result <- suppressWarnings(
      try(Sys.setlocale("LC_TIME", loc), silent = TRUE)
    )

    if (!inherits(result, "try-error") &&
        !is.na(result)) {
      locale_set <- TRUE
      break
    }
  }

  if (!locale_set) {
    warning("Could not set English date locale.")
  }

  raw_values <- trimws(
    archive$publication_date_raw[missing_idx]
  )

  # Remove weekday prefix and GMT/UTC suffix
  # while retaining the original clock time.
  cleaned <- sub(
    "^[A-Za-z]{3},\\s*",
    "",
    raw_values
  )

  cleaned <- sub(
    "\\s+(GMT|UTC)$",
    "",
    cleaned,
    ignore.case = TRUE
  )

  parsed <- as.POSIXct(
    strptime(
      cleaned,
      format = "%d %b %Y %H:%M:%S",
      tz = "UTC"
    ),
    tz = "UTC"
  )

  # Only fill previously missing dates
  recovered <- !is.na(parsed)

  archive$publication_date_utc[
    missing_idx[recovered]
  ] <- parsed[recovered]

  after <- sum(is.na(archive$publication_date_utc))

  # Confirm existing article records were preserved
  stopifnot(
    nrow(archive) > 0,
    before >= after,
    !anyDuplicated(archive$article_key)
  )

  # Save repaired archive
  saveRDS(archive, archive_path)

  utils::write.csv(
    archive,
    csv_path,
    row.names = FALSE,
    na = ""
  )

  cat("\n====================================\n")
  cat("HISTORICAL DATE REPAIR COMPLETE\n")
  cat("====================================\n")

  cat("Total articles:", nrow(archive), "\n")
  cat("Missing before:", before, "\n")
  cat("Recovered:", before - after, "\n")
  cat("Missing after:", after, "\n")

  cat(
    "Date completeness:",
    round(
      100 * mean(!is.na(
        archive$publication_date_utc
      )),
      2
    ),
    "%\n"
  )

  cat("Backup:", backup_path, "\n")

  invisible(archive)
}
