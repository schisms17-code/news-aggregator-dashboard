
# ============================================================
# NEWS AGGREGATOR
# PHASE 2 - STEP 3
# RUN NEWS COLLECTION
# ============================================================

# ------------------------------------------------------------
# 1. CONFIRM PROJECT DIRECTORY
# ------------------------------------------------------------

project_root <- "C:/Users/vonne/OneDrive/Desktop/news_aggregator"

if (!dir.exists(project_root)) {
  stop("Project directory could not be found.")
}

setwd(project_root)

cat("\n====================================\n")
cat("NEWS AGGREGATOR - COLLECTION RUNNER\n")
cat("====================================\n")

cat("Working directory:", getwd(), "\n")


# ------------------------------------------------------------
# 2. LOCATE COLLECTION ENGINE
# ------------------------------------------------------------

possible_scripts <- c(
  "R/01_collect_news.R",
  "R/01_collect_news/01_collect_news.R"
)

existing_scripts <- possible_scripts[
  file.exists(possible_scripts)
]

if (length(existing_scripts) == 0) {

  stop(
    paste(
      "Could not find the news collection engine.",
      "Expected one of these files:",
      paste(possible_scripts, collapse = "\n")
    )
  )

}

# Prefer the script directly inside the R folder
collector_script <- existing_scripts[1]

cat("\nLoading collection engine:\n")
cat(collector_script, "\n")

source(
  normalizePath(
    collector_script,
    winslash = "/",
    mustWork = TRUE
  ),
  local = FALSE
)


# ------------------------------------------------------------
# 3. VERIFY COLLECTION FUNCTION
# ------------------------------------------------------------

if (!exists("collect_all_news", mode = "function")) {
  stop("The collect_all_news() function was not loaded.")
}

cat("\nCollection engine loaded successfully.\n")


# ------------------------------------------------------------
# 4. VERIFY SOURCE CONFIGURATION
# ------------------------------------------------------------

source_file <- "config/news_sources.csv"

if (!file.exists(source_file)) {
  stop("News source configuration file is missing.")
}

sources <- read.csv(
  source_file,
  stringsAsFactors = FALSE
)

cat("\nConfigured news sources:", nrow(sources), "\n")
cat("Active news sources:", sum(sources$active == TRUE, na.rm = TRUE), "\n")


# ------------------------------------------------------------
# 5. RUN COLLECTION
# ------------------------------------------------------------

cat("\nStarting RSS collection...\n")

news_data <- collect_all_news(
  source_file = source_file
)


# ------------------------------------------------------------
# 6. VERIFY OUTPUT
# ------------------------------------------------------------

if (is.null(news_data) || nrow(news_data) == 0) {
  stop("Collection finished without returning any articles.")
}

cat("\n====================================\n")
cat("COLLECTION RUNNER FINISHED\n")
cat("====================================\n")

cat("Total articles collected:", nrow(news_data), "\n")

cat(
  "Unique sources:",
  dplyr::n_distinct(news_data$source_name),
  "\n"
)

cat("\nMost recent articles:\n")

print(
  news_data %>%
    select(
      article_title,
      source_name,
      source_region,
      source_category,
      publication_date_utc
    ) %>%
    head(10)
)

cat("\nCollection output files:\n")

output_files <- c(
  "data/processed/news_articles_latest.rds",
  "data/processed/news_articles_latest.csv"
)

for (file in output_files) {
  cat(
    file,
    ":",
    file.exists(file),
    "\n"
  )
}

cat("\nPhase 2 collection step completed.\n")
