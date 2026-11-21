# Historical News Archive Builder
# Reads existing timestamped RSS snapshots without changing collector or dashboard.

build_news_archive <- function(project_dir = getwd()) {
  raw_dir <- file.path(project_dir, "data", "raw")
  output_dir <- file.path(project_dir, "data", "processed")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  paths <- sort(list.files(raw_dir, pattern = "^news_snapshot_[0-9]{8}_[0-9]{6}\\.rds$", full.names = TRUE))
  if (!length(paths)) stop("No timestamped RSS snapshots found in: ", raw_dir)

  snapshot_time <- function(path) {
    stamp <- sub("^news_snapshot_([0-9]{8}_[0-9]{6})\\.rds$", "\\1", basename(path))
    as.POSIXct(strptime(stamp, format = "%Y%m%d_%H%M%S", tz = "America/Chicago"))
  }

  loaded <- lapply(paths, function(path) {
    tryCatch({
      x <- readRDS(path)
      if (is.list(x) && !is.data.frame(x) && is.data.frame(x$articles)) x <- x$articles
      if (!is.data.frame(x)) stop("Not an article data frame")
      if (!"article_title" %in% names(x)) stop("Missing article_title")
      x <- as.data.frame(x, stringsAsFactors = FALSE)
      if (!nrow(x)) return(NULL)
      x$.snapshot_time <- rep(snapshot_time(path), nrow(x))
      x$.snapshot_file <- rep(basename(path), nrow(x))
      x
    }, error = function(e) {
      warning("Skipping ", basename(path), ": ", conditionMessage(e), call. = FALSE)
      NULL
    })
  })
  loaded <- Filter(Negate(is.null), loaded)
  if (!length(loaded)) stop("No usable snapshots")

  # Align columns across collection versions.
  columns <- unique(unlist(lapply(loaded, names), use.names = FALSE))
  loaded <- lapply(loaded, function(x) {
    for (nm in setdiff(columns, names(x))) x[[nm]] <- NA
    x[columns]
  })
  combined <- do.call(rbind, loaded)
  rownames(combined) <- NULL

  # Prefer the collector's stable article_key, then normalized_url, article_url,
  # and finally a source-and-title fallback.
  clean <- function(x) {
    x <- as.character(x)
    x[is.na(x)] <- ""
    trimws(x)
  }
  key <- rep("", nrow(combined))
  for (field in c("article_key", "normalized_url", "article_url")) {
    if (field %in% names(combined)) {
      candidate <- clean(combined[[field]])
      missing <- !nzchar(key) & nzchar(candidate)
      key[missing] <- tolower(candidate[missing])
    }
  }
  fallback <- paste(tolower(clean(combined$source_name)), tolower(clean(combined$article_title)), sep = "||")
  key[!nzchar(key)] <- fallback[!nzchar(key)]
  # Avoid merging completely blank identifiers.
  empty <- !nzchar(gsub("[| ]", "", key))
  key[empty] <- paste0("unidentified_row_", which(empty))
  combined$.archive_key <- key

  # An article can occur more than once within a single snapshot; count
  # distinct snapshot files, not rows, as snapshots_seen.
  groups <- split(seq_len(nrow(combined)), combined$.archive_key)
  chosen <- integer(length(groups))
  first_seen <- last_seen <- as.POSIXct(rep(NA_real_, length(groups)), origin = "1970-01-01", tz = "UTC")
  snapshots_seen <- integer(length(groups))
  i <- 0L
  for (idx in groups) {
    i <- i + 1L
    timestamps <- as.numeric(combined$.snapshot_time[idx])
    chosen[i] <- idx[order(timestamps, na.last = TRUE, decreasing = TRUE)[1]]
    first_seen[i] <- as.POSIXct(min(timestamps, na.rm = TRUE), origin = "1970-01-01", tz = "UTC")
    last_seen[i] <- as.POSIXct(max(timestamps, na.rm = TRUE), origin = "1970-01-01", tz = "UTC")
    snapshots_seen[i] <- length(unique(combined$.snapshot_file[idx]))
  }

  archive <- combined[chosen, setdiff(names(combined), c(".snapshot_time", ".snapshot_file", ".archive_key")), drop = FALSE]
  archive$first_seen <- first_seen
  archive$last_seen <- last_seen
  archive$snapshots_seen <- snapshots_seen
  if ("publication_date_utc" %in% names(archive)) {
    archive <- archive[order(archive$publication_date_utc, decreasing = TRUE, na.last = TRUE), , drop = FALSE]
  }
  rownames(archive) <- NULL

  rds_path <- file.path(output_dir, "news_articles_archive.rds")
  csv_path <- file.path(output_dir, "news_articles_archive.csv")
  saveRDS(archive, rds_path)
  utils::write.csv(archive, csv_path, row.names = FALSE, na = "")

  cat("Historical news archive created successfully.\n")
  cat("Snapshots loaded:", length(loaded), "of", length(paths), "\n")
  cat("Total snapshot article rows:", nrow(combined), "\n")
  cat("Unique archived articles:", nrow(archive), "\n")
  cat("RDS:", rds_path, "\n")
  cat("CSV:", csv_path, "\n")
  invisible(archive)
}
