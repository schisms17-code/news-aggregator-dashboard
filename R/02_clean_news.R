
# ============================================================
# NEWS AGGREGATOR
# PHASE 3: DATA CLEANING AND PREPARATION
# ============================================================

# Project directory
project_dir <- "C:/Users/vonne/OneDrive/Desktop/news_aggregator"
setwd(project_dir)

# Load packages
library(tidyverse)
library(lubridate)
library(janitor)

cat("\n====================================\n")
cat("NEWS AGGREGATOR - DATA CLEANING\n")
cat("====================================\n\n")

# ------------------------------------------------------------
# 1. LOAD RAW COLLECTED ARTICLES
# ------------------------------------------------------------

input_file <- "data/processed/news_articles_latest.rds"

if (!file.exists(input_file)) {
  stop("Collected news file not found: ", input_file)
}

news_raw <- readRDS(input_file)

cat("Raw articles loaded:", nrow(news_raw), "\n")
cat("Raw columns:", ncol(news_raw), "\n\n")

# ------------------------------------------------------------
# 2. STANDARDIZE AND CLEAN TEXT
# ------------------------------------------------------------

clean_text <- function(x) {
  x <- as.character(x)
  x <- str_replace_all(x, "[\r\n\t]", " ")
  x <- str_squish(x)
  x[x == ""] <- NA_character_
  x
}

news_clean <- news_raw %>%
  clean_names() %>%
  mutate(
    article_title = clean_text(article_title),
    article_description = clean_text(article_description),
    article_url = str_trim(as.character(article_url)),
    source_name = clean_text(source_name),
    source_region = clean_text(source_region),
    source_category = clean_text(source_category),
    article_domain = clean_text(article_domain)
  )

# ------------------------------------------------------------
# 3. REMOVE INVALID RECORDS
# ------------------------------------------------------------

before_filtering <- nrow(news_clean)

news_clean <- news_clean %>%
  filter(
    !is.na(article_title),
    !is.na(article_url),
    str_detect(article_url, "^https?://"),
    !is.na(source_name)
  )

removed_invalid <- before_filtering - nrow(news_clean)

cat("Invalid records removed:", removed_invalid, "\n")

# ------------------------------------------------------------
# 4. STANDARDIZE PUBLICATION DATES
# ------------------------------------------------------------

news_clean <- news_clean %>%
  mutate(
    publication_date_utc = as.POSIXct(
      publication_date_utc,
      tz = "UTC"
    ),
    collected_at_utc = as.POSIXct(
      collected_at_utc,
      tz = "UTC"
    )
  )

# Retain articles without a valid publication date,
# but flag them for data-quality reporting.

news_clean <- news_clean %>%
  mutate(
    date_missing = is.na(publication_date_utc),
    publication_year = year(publication_date_utc),
    publication_month = month(
      publication_date_utc,
      label = TRUE,
      abbr = FALSE
    ),
    publication_day = day(publication_date_utc),
    publication_date = as.Date(publication_date_utc)
  )

# ------------------------------------------------------------
# 5. STANDARDIZE REGIONS AND CATEGORIES
# ------------------------------------------------------------

news_clean <- news_clean %>%
  mutate(
    source_region = str_to_title(source_region),
    source_category = str_squish(source_category),
    source_category = case_when(
      str_detect(
        str_to_lower(source_category),
        "crime|public safety"
      ) ~ "Crime & Public Safety",

      str_detect(
        str_to_lower(source_category),
        "local government"
      ) ~ "Local Government",

      str_detect(
        str_to_lower(source_category),
        "politics"
      ) ~ "Politics",

      str_detect(
        str_to_lower(source_category),
        "business|econom"
      ) ~ "Business & Economy",

      str_detect(
        str_to_lower(source_category),
        "technology|tech"
      ) ~ "Technology",

      str_detect(
        str_to_lower(source_category),
        "health"
      ) ~ "Public Health",

      str_detect(
        str_to_lower(source_category),
        "education"
      ) ~ "Education",

      TRUE ~ source_category
    )
  )

# ------------------------------------------------------------
# 6. CREATE ANALYTICAL FIELDS
# ------------------------------------------------------------

news_clean <- news_clean %>%
  mutate(
    title_word_count = str_count(
      article_title,
      "\\S+"
    ),

    description_word_count = if_else(
      is.na(article_description),
      0L,
      str_count(article_description, "\\S+")
    ),

    article_hour_utc = hour(publication_date_utc),

    article_day_of_week = wday(
      publication_date_utc,
      label = TRUE,
      abbr = FALSE
    ),

    story_key = str_to_lower(
      str_replace_all(
        article_title,
        "[^[:alnum:]]+",
        " "
      )
    )
  )

# ------------------------------------------------------------
# 7. IDENTIFY DUPLICATES
# ------------------------------------------------------------

# Preserve syndicated stories from different sources.
# Remove repeated records from the same source and URL.

before_deduplication <- nrow(news_clean)

news_clean <- news_clean %>%
  mutate(
    normalized_url = str_remove(
      article_url,
      "[?#].*$"
    ),
    normalized_url = str_remove(
      normalized_url,
      "/+$"
    )
  ) %>%
  arrange(desc(publication_date_utc)) %>%
  distinct(
    source_name,
    normalized_url,
    .keep_all = TRUE
  )

removed_duplicates <- before_deduplication - nrow(news_clean)

cat("Duplicate records removed:", removed_duplicates, "\n")

# ------------------------------------------------------------
# 8. FINAL ORGANIZATION
# ------------------------------------------------------------

news_clean <- news_clean %>%
  arrange(desc(publication_date_utc)) %>%
  select(
    article_title,
    article_description,
    article_url,
    publication_date_raw,
    publication_date_utc,
    publication_date,
    publication_year,
    publication_month,
    publication_day,
    article_hour_utc,
    article_day_of_week,
    article_guid,
    source_name,
    source_region,
    source_category,
    article_domain,
    title_word_count,
    description_word_count,
    date_missing,
    story_key,
    normalized_url,
    everything()
  ) %>%
  relocate(
    story_key,
    .after = article_title
  )

# ------------------------------------------------------------
# 9. CREATE DATA QUALITY REPORT
# ------------------------------------------------------------

quality_report <- tibble(
  metric = c(
    "Raw articles",
    "Clean articles",
    "Invalid records removed",
    "Duplicate records removed",
    "Missing publication dates",
    "Unique sources",
    "Unique regions",
    "Unique categories"
  ),

  value = c(
    nrow(news_raw),
    nrow(news_clean),
    removed_invalid,
    removed_duplicates,
    sum(news_clean$date_missing),
    n_distinct(news_clean$source_name),
    n_distinct(news_clean$source_region),
    n_distinct(news_clean$source_category)
  )
)

# ------------------------------------------------------------
# 10. SAVE CLEANED DATA
# ------------------------------------------------------------

dir.create(
  "data/processed",
  recursive = TRUE,
  showWarnings = FALSE
)

saveRDS(
  news_clean,
  "data/processed/news_articles_clean.rds"
)

write_csv(
  news_clean,
  "data/processed/news_articles_clean.csv"
)

write_csv(
  quality_report,
  "data/processed/news_data_quality_report.csv"
)

# ------------------------------------------------------------
# 11. PRINT SUMMARY
# ------------------------------------------------------------

cat("\n====================================\n")
cat("DATA CLEANING COMPLETE\n")
cat("====================================\n\n")

print(quality_report)

cat("\nArticles by region:\n")

print(
  news_clean %>%
    count(source_region, sort = TRUE)
)

cat("\nArticles by category:\n")

print(
  news_clean %>%
    count(source_category, sort = TRUE)
)

cat("\nSaved files:\n")
cat("data/processed/news_articles_clean.rds\n")
cat("data/processed/news_articles_clean.csv\n")
cat("data/processed/news_data_quality_report.csv\n")

cat("\n====================================\n")
cat("PHASE 3 CLEANING FINISHED\n")
cat("====================================\n")
