# ============================================================
# NEWS AGGREGATOR
# Script: 01_collect_news.R
# Purpose: Collect articles from configured RSS feeds
# Project: San Antonio / Texas / National / International News
# ============================================================


# ------------------------------------------------------------
# 1. LOAD REQUIRED PACKAGES
# ------------------------------------------------------------

required_packages <- c(
  "httr2",
  "xml2",
  "dplyr",
  "stringr",
  "purrr",
  "tibble",
  "readr"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0) {
  stop(
    "The following packages are missing: ",
    paste(missing_packages, collapse = ", "),
    "\nInstall them before running this script."
  )
}

library(httr2)
library(xml2)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)
library(readr)


# ------------------------------------------------------------
# 2. PROJECT PATHS
# ------------------------------------------------------------

project_root <- getwd()

config_path <- file.path(
  project_root,
  "config",
  "news_sources.csv"
)

raw_dir <- file.path(project_root, "data", "raw")

processed_dir <- file.path(
  project_root,
  "data",
  "processed"
)

logs_dir <- file.path(project_root, "logs")

dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(logs_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(config_path)) {
  stop(
    "Cannot find config/news_sources.csv. ",
    "Make sure your working directory is the project root."
  )
}


# ------------------------------------------------------------
# 3. CLEAN HTML AND TEXT
# ------------------------------------------------------------

clean_html_text <- function(x) {

  if (is.null(x) || length(x) == 0 || is.na(x[1])) {
    return("")
  }

  x <- as.character(x[1])

  if (nchar(trimws(x)) == 0) {
    return("")
  }

  cleaned <- tryCatch({

    document <- xml2::read_html(
      paste0(
        "<html><body>",
        x,
        "</body></html>"
      ),
      options = c("RECOVER", "NOERROR", "NOWARNING")
    )

    xml2::xml_text(
      xml2::xml_find_first(document, "//body")
    )

  }, error = function(e) {
    x
  })

  cleaned <- stringr::str_replace_all(
    cleaned,
    "[\\r\\n\\t]+",
    " "
  )

  cleaned <- stringr::str_squish(cleaned)

  return(cleaned)
}


# ------------------------------------------------------------
# 4. EXTRACT XML FIELDS
# ------------------------------------------------------------

get_xml_field <- function(node, field_names) {

  for (field in field_names) {

    xpath <- paste0(
      ".//*[local-name()='",
      field,
      "']"
    )

    field_node <- xml2::xml_find_first(
      node,
      xpath
    )

    if (!inherits(field_node, "xml_missing")) {

      value <- xml2::xml_text(field_node)

      if (!is.na(value) && nzchar(trimws(value))) {
        return(trimws(value))
      }
    }
  }

  return("")
}


# ------------------------------------------------------------
# 5. EXTRACT ARTICLE LINKS
# ------------------------------------------------------------

get_article_link <- function(node) {

  links <- xml2::xml_find_all(
    node,
    ".//*[local-name()='link']"
  )

  if (length(links) == 0) {
    return("")
  }

  # Prefer Atom alternate links when available
  for (link_node in links) {

    href <- xml2::xml_attr(link_node, "href")
    rel <- xml2::xml_attr(link_node, "rel")

    if (
      !is.na(href) &&
      nzchar(trimws(href)) &&
      (is.na(rel) || rel == "alternate")
    ) {
      return(trimws(href))
    }
  }

  # Fall back to RSS link text
  for (link_node in links) {

    link_text <- trimws(xml2::xml_text(link_node))

    if (nzchar(link_text)) {
      return(link_text)
    }
  }

  return("")
}


# ------------------------------------------------------------
# 6. PUBLICATION DATE PARSER
# Supports:
# - Google News GMT and UTC dates
# - RFC-style RSS dates
# - ISO 8601 dates
# - Numeric timezone offsets
# - Dates without timezone information
# ------------------------------------------------------------

parse_news_date <- function(x) {

  if (is.null(x) || length(x) == 0) {
    return(as.POSIXct(character(), tz = "UTC"))
  }

  x <- trimws(as.character(x))

  result <- as.POSIXct(
    rep(NA_real_, length(x)),
    origin = "1970-01-01",
    tz = "UTC"
  )

  # English month abbreviations, independent of Windows locale.
  month_names <- c(
    jan = "01", feb = "02", mar = "03",
    apr = "04", may = "05", jun = "06",
    jul = "07", aug = "08", sep = "09",
    oct = "10", nov = "11", dec = "12"
  )

  for (i in seq_along(x)) {

    if (is.na(x[i]) || !nzchar(x[i])) next

    date_string <- trimws(x[i])

    # ----------------------------------------------------------
    # A. RFC-style RSS dates (GMT, UTC, or numeric offset)
    # ----------------------------------------------------------

    rfc_pattern <- paste0(
      "^(?:[A-Za-z]{3},\\s*)?",
      "(\\d{1,2})\\s+",
      "([A-Za-z]{3})\\s+",
      "(\\d{4})\\s+",
      "(\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?)",
      "(?:\\s+(GMT|UTC|[+-]\\d{2}:?\\d{2}))?$"
    )

    matches <- regmatches(
      date_string,
      regexec(
        rfc_pattern,
        date_string,
        ignore.case = TRUE,
        perl = TRUE
      )
    )[[1]]

    if (length(matches) > 0) {

      day <- matches[2]
      month <- tolower(matches[3])
      year <- matches[4]
      clock <- matches[5]
      timezone <- toupper(matches[6])

      month_number <- unname(month_names[month])

      if (length(month_number) == 1 && !is.na(month_number)) {

        parsed <- suppressWarnings(
          as.POSIXct(
            paste(day, month_number, year, clock),
            format = "%d %m %Y %H:%M:%OS",
            tz = "UTC"
          )
        )

        if (!is.na(parsed)) {

          offset_seconds <- 0

          if (!is.na(timezone) && grepl("^[+-]", timezone)) {

            offset <- gsub(":", "", timezone)
            sign <- if (substr(offset, 1, 1) == "+") 1 else -1
            hours <- as.numeric(substr(offset, 2, 3))
            minutes <- as.numeric(substr(offset, 4, 5))

            offset_seconds <- sign * (hours * 3600 + minutes * 60)
          }

          result[i] <- parsed - offset_seconds
          next
        }
      }
    }

    # ----------------------------------------------------------
    # B. ISO 8601 timestamps and timezone offsets
    # ----------------------------------------------------------

    iso_string <- date_string
    timezone_offset <- 0

    if (grepl("Z$", iso_string, ignore.case = TRUE)) {

      iso_string <- sub("Z$", "", iso_string, ignore.case = TRUE)

    } else if (grepl("[+-][0-9]{2}:?[0-9]{2}$", iso_string)) {

      offset <- regmatches(
        iso_string,
        regexpr("[+-][0-9]{2}:?[0-9]{2}$", iso_string)
      )

      iso_string <- sub("[+-][0-9]{2}:?[0-9]{2}$", "", iso_string)
      offset <- gsub(":", "", offset)

      sign <- if (substr(offset, 1, 1) == "+") 1 else -1
      hours <- as.numeric(substr(offset, 2, 3))
      minutes <- as.numeric(substr(offset, 4, 5))

      timezone_offset <- sign * (hours * 3600 + minutes * 60)
    }

    parsed <- suppressWarnings(
      as.POSIXct(
        iso_string,
        format = "%Y-%m-%dT%H:%M:%OS",
        tz = "UTC"
      )
    )

    if (is.na(parsed)) {
      parsed <- suppressWarnings(
        as.POSIXct(
          iso_string,
          format = "%Y-%m-%d %H:%M:%OS",
          tz = "UTC"
        )
      )
    }

    if (is.na(parsed)) {
      parsed <- suppressWarnings(
        as.POSIXct(
          iso_string,
          format = "%Y-%m-%d",
          tz = "UTC"
        )
      )
    }

    if (!is.na(parsed)) {
      result[i] <- parsed - timezone_offset
    }
  }

  return(result)
}


# ------------------------------------------------------------
# 7. PARSE AN INDIVIDUAL RSS OR ATOM FEED
# ------------------------------------------------------------

parse_news_feed <- function(feed_url, source_name,
                            source_region, source_category) {

  response <- httr2::request(feed_url) |>
    httr2::req_user_agent(
      "SanAntonioNewsAggregator/1.0 (RSS Reader)"
    ) |>
    httr2::req_timeout(30) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform()

  httr2::resp_check_status(response)

  xml_content <- httr2::resp_body_string(response)

  document <- xml2::read_xml(
    xml_content,
    options = c("RECOVER", "NOERROR", "NOWARNING")
  )

  # Support RSS item and Atom entry elements.

  article_nodes <- xml2::xml_find_all(
    document,
    "//*[local-name()='item' or local-name()='entry']"
  )

  if (length(article_nodes) == 0) {
    return(tibble())
  }

  collected_at <- as.POSIXct(
    Sys.time(),
    tz = "UTC"
  )

  articles <- purrr::map_dfr(
    article_nodes,
    function(node) {

      title <- get_xml_field(
        node,
        c("title")
      )

      description <- get_xml_field(
        node,
        c("description", "summary", "encoded", "content")
      )

      article_url <- get_article_link(node)

      publication_raw <- get_xml_field(
        node,
        c("pubDate", "published", "updated", "date")
      )

      article_guid <- get_xml_field(
        node,
        c("guid", "id")
      )

      title <- clean_html_text(title)
      description <- clean_html_text(description)

      if (nzchar(article_url)) {
        article_url <- trimws(article_url)
      }

      if (!nzchar(article_guid)) {
        article_guid <- article_url
      }

      tibble(
        article_title = title,
        article_description = description,
        article_url = article_url,
        publication_date_raw = publication_raw,
        publication_date_utc = parse_news_date(publication_raw),
        article_guid = article_guid,
        source_name = source_name,
        source_region = source_region,
        source_category = source_category,
        feed_url = feed_url,
        collected_at_utc = collected_at
      )
    }
  )

  articles <- articles %>%
    filter(
      !is.na(article_title),
      nzchar(article_title)
    )

  return(articles)
}


# ------------------------------------------------------------
# 8. COLLECT ARTICLES FROM ALL ACTIVE SOURCES
# ------------------------------------------------------------

collect_all_news <- function(
    config_file = config_path,
    save_outputs = TRUE) {

  cat("\n")
  cat("============================================\n")
  cat("       NEWS AGGREGATOR - RSS COLLECTION     \n")
  cat("============================================\n\n")

  if (!file.exists(config_file)) {
    stop("News source configuration file not found.")
  }

  sources <- readr::read_csv(
    config_file,
    show_col_types = FALSE
  )

  required_columns <- c(
    "source_name",
    "region",
    "category",
    "feed_url",
    "active"
  )

  missing_columns <- setdiff(
    required_columns,
    names(sources)
  )

  if (length(missing_columns) > 0) {
    stop(
      "Missing columns in news_sources.csv: ",
      paste(missing_columns, collapse = ", ")
    )
  }

  # Interpret active values consistently.

  sources <- sources %>%
    mutate(
      active_flag = case_when(
        tolower(as.character(active)) %in%
          c("true", "1", "yes", "y") ~ TRUE,

        TRUE ~ FALSE
      )
    ) %>%
    filter(
      active_flag,
      !is.na(feed_url),
      nzchar(feed_url)
    )

  if (nrow(sources) == 0) {
    stop("No active RSS sources were found.")
  }

  cat("Active RSS sources:", nrow(sources), "\n\n")

  all_articles <- list()
  feed_logs <- list()

  for (i in seq_len(nrow(sources))) {

    source <- sources[i, ]

    source_name <- as.character(source$source_name)
    source_region <- as.character(source$region)
    source_category <- as.character(source$category)
    feed_url <- as.character(source$feed_url)

    cat(
      "[",
      i,
      "/",
      nrow(sources),
      "] Collecting: ",
      source_name,
      "\n",
      sep = ""
    )

    start_time <- Sys.time()

    result <- tryCatch({

      articles <- parse_news_feed(
        feed_url = feed_url,
        source_name = source_name,
        source_region = source_region,
        source_category = source_category
      )

      list(
        success = TRUE,
        articles = articles,
        message = "Feed collected successfully"
      )

    }, error = function(e) {

      list(
        success = FALSE,
        articles = tibble(),
        message = conditionMessage(e)
      )
    })

    elapsed <- round(
      as.numeric(
        difftime(Sys.time(), start_time, units = "secs")
      ),
      2
    )

    article_count <- nrow(result$articles)

    if (result$success) {

      cat(
        "    SUCCESS - ",
        article_count,
        " articles collected (",
        elapsed,
        " seconds)\n",
        sep = ""
      )

      all_articles[[length(all_articles) + 1]] <-
        result$articles

      status <- "SUCCESS"

    } else {

      cat(
        "    FAILED - ",
        result$message,
        "\n",
        sep = ""
      )

      status <- "FAILED"
    }

    feed_logs[[length(feed_logs) + 1]] <- tibble(
      source_name = source_name,
      feed_url = feed_url,
      status = status,
      article_count = article_count,
      message = result$message,
      elapsed_seconds = elapsed,
      collected_at_utc = as.POSIXct(
        Sys.time(),
        tz = "UTC"
      )
    )
  }


  # ----------------------------------------------------------
  # 9. COMBINE AND STANDARDIZE ARTICLES
  # ----------------------------------------------------------

  if (length(all_articles) > 0) {

    articles <- bind_rows(all_articles)

  } else {

    articles <- tibble(
      article_title = character(),
      article_description = character(),
      article_url = character(),
      publication_date_raw = character(),
      publication_date_utc = as.POSIXct(
        character(),
        tz = "UTC"
      ),
      article_guid = character(),
      source_name = character(),
      source_region = character(),
      source_category = character(),
      feed_url = character(),
      collected_at_utc = as.POSIXct(
        character(),
        tz = "UTC"
      )
    )
  }

  # Generate a normalized article key.

  articles <- articles %>%
    mutate(
      normalized_url = stringr::str_to_lower(
        stringr::str_remove(
          stringr::str_trim(article_url),
          "/+$"
        )
      ),

      article_key = if_else(
        !is.na(normalized_url) & nzchar(normalized_url),
        normalized_url,
        paste(
          stringr::str_to_lower(article_title),
          source_name,
          sep = "_"
        )
      ),

      article_domain = stringr::str_extract(
        article_url,
        "^(?:https?://)?([^/]+)"
      ),

      article_domain = stringr::str_remove(
        article_domain,
        "^www\\."
      )
    )

  # Keep the most recent collected copy of duplicate URLs.

  articles <- articles %>%
    arrange(
      desc(collected_at_utc),
      desc(publication_date_utc)
    ) %>%
    distinct(
      article_key,
      .keep_all = TRUE
    ) %>%
    arrange(
      desc(publication_date_utc),
      desc(collected_at_utc)
    )


  # ----------------------------------------------------------
  # 10. BUILD FEED LOG
  # ----------------------------------------------------------

  feed_log <- bind_rows(feed_logs)

  timestamp <- format(
    Sys.time(),
    "%Y%m%d_%H%M%S"
  )


  # ----------------------------------------------------------
  # 11. SAVE OUTPUTS
  # ----------------------------------------------------------

  if (save_outputs) {

    # Raw snapshot

    snapshot_path <- file.path(
      raw_dir,
      paste0("news_snapshot_", timestamp, ".rds")
    )

    saveRDS(
      articles,
      snapshot_path
    )

    # Latest RDS

    saveRDS(
      articles,
      file.path(
        processed_dir,
        "news_articles_latest.rds"
      )
    )

    # Latest CSV

    readr::write_csv(
      articles,
      file.path(
        processed_dir,
        "news_articles_latest.csv"
      )
    )

    # Feed log

    log_path <- file.path(
      logs_dir,
      paste0("feed_log_", timestamp, ".csv")
    )

    readr::write_csv(
      feed_log,
      log_path
    )

    cat("\nSaved files:\n")
    cat("  Raw snapshot: ", snapshot_path, "\n", sep = "")
    cat("  Latest RDS: data/processed/news_articles_latest.rds\n")
    cat("  Latest CSV: data/processed/news_articles_latest.csv\n")
    cat("  Feed log: ", log_path, "\n", sep = "")
  }


  # ----------------------------------------------------------
  # 12. COLLECTION SUMMARY
  # ----------------------------------------------------------

  successful_feeds <- sum(feed_log$status == "SUCCESS")
  failed_feeds <- sum(feed_log$status == "FAILED")

  cat("\n")
  cat("============================================\n")
  cat("             COLLECTION SUMMARY             \n")
  cat("============================================\n")

  cat("Active sources:       ", nrow(sources), "\n")
  cat("Successful feeds:     ", successful_feeds, "\n")
  cat("Failed feeds:         ", failed_feeds, "\n")
  cat("Total articles:       ", nrow(articles), "\n")
  cat(
    "Missing dates:        ",
    sum(is.na(articles$publication_date_utc)),
    "\n"
  )

  if (nrow(articles) > 0) {

    cat("\nArticles by region:\n")

    print(
      articles %>%
        count(source_region, sort = TRUE)
    )

    cat("\nArticles by category:\n")

    print(
      articles %>%
        count(source_category, sort = TRUE)
    )
  }

  cat("\nCollection completed.\n")
  cat("============================================\n")

  invisible(
    list(
      articles = articles,
      feed_log = feed_log
    )
  )
}


# ============================================================
# END OF SCRIPT
#
# To collect news, run:
#
# source("R/01_collect_news.R")
# collection_results <- collect_all_news()
#
# ============================================================
