
# ============================================================
# NEWS AGGREGATOR
# PHASE 1: PROJECT INITIALIZATION
# ============================================================

# Confirm project directory
project_dir <- getwd()

message("Initializing News Aggregator...")
message("Project location: ", project_dir)

# ------------------------------------------------------------
# 1. CREATE PROJECT DIRECTORIES
# ------------------------------------------------------------

folders <- c(
  "data",
  "data/raw",
  "data/processed",
  "data/archive",
  "R",
  "scripts",
  "config",
  "reports",
  "www",
  "logs"
)

for (folder in folders) {
  dir.create(
    file.path(project_dir, folder),
    recursive = TRUE,
    showWarnings = FALSE
  )
}

# ------------------------------------------------------------
# 2. CREATE NEWS CATEGORY CONFIGURATION
# ------------------------------------------------------------

categories <- data.frame(
  category = c(
    "Politics",
    "Local Government",
    "Crime & Public Safety",
    "Business & Economy",
    "Technology",
    "Public Health",
    "Education"
  ),
  active = TRUE,
  stringsAsFactors = FALSE
)

write.csv(
  categories,
  file.path(project_dir, "config/news_categories.csv"),
  row.names = FALSE
)

# ------------------------------------------------------------
# 3. CREATE RSS SOURCE CONFIGURATION
# ------------------------------------------------------------

sources <- data.frame(
  source_name = character(),
  region = character(),
  category = character(),
  feed_url = character(),
  active = logical()
)

write.csv(
  sources,
  file.path(project_dir, "config/news_sources.csv"),
  row.names = FALSE
)

# ------------------------------------------------------------
# 4. CREATE PROJECT README
# ------------------------------------------------------------

readme <- c(
  "# News Intelligence & Aggregator",
  "",
  "## Project Overview",
  "",
  "An R-based news aggregation and analytics application.",
  "",
  "The application will collect publicly available news articles",
  "through RSS feeds and analyze news coverage across multiple",
  "geographic regions and subject categories.",
  "",
  "## Geographic Scope",
  "",
  "- San Antonio",
  "- Texas",
  "- United States",
  "- International",
  "",
  "## News Categories",
  "",
  "- Politics",
  "- Local Government",
  "- Crime & Public Safety",
  "- Business & Economy",
  "- Technology",
  "- Public Health",
  "- Education",
  "",
  "## Technology",
  "",
  "- R",
  "- RStudio",
  "- Shiny",
  "- RSS/XML",
  "- Tidyverse",
  "- Tidytext",
  "- ggplot2",
  "",
  "## Project Status",
  "",
  "Phase 1: Project initialization",
  "",
  "## Data Collection",
  "",
  "Publicly available RSS feeds. No paid news API required.",
  "",
  "## Author",
  "",
  "Michael Serna"
)

writeLines(readme, "README.md")

# ------------------------------------------------------------
# 5. CREATE GITIGNORE
# ------------------------------------------------------------

gitignore <- c(
  ".Rhistory",
  ".RData",
  ".Ruserdata",
  ".Rproj.user/",
  "data/raw/*",
  "data/archive/*",
  "logs/*",
  "*.log",
  ".DS_Store"
)

writeLines(gitignore, ".gitignore")

# ------------------------------------------------------------
# 6. CREATE PACKAGE INSTALLATION SCRIPT
# ------------------------------------------------------------

package_script <- c(
  "# NEWS AGGREGATOR - REQUIRED PACKAGES",
  "",
  "required_packages <- c(",
  '  "shiny",',
  '  "bslib",',
  '  "tidyverse",',
  '  "httr2",',
  '  "xml2",',
  '  "lubridate",',
  '  "tidytext",',
  '  "DT",',
  '  "janitor",',
  '  "here",',
  '  "scales",',
  '  "plotly",',
  '  "stopwords"',
  ")",
  "",
  "installed <- rownames(installed.packages())",
  "",
  "missing_packages <- setdiff(",
  "  required_packages,",
  "  installed",
  ")",
  "",
  "if (length(missing_packages) > 0) {",
  "  install.packages(missing_packages)",
  "}",
  "",
  "cat('\\nPackage verification complete.\\n')",
  "",
  "for (pkg in required_packages) {",
  "  cat(pkg, ': ',",
  "      ifelse(requireNamespace(pkg, quietly = TRUE),",
  "             'INSTALLED', 'MISSING'), '\\n')",
  "}"
)

writeLines(package_script, "R/00_packages.R")

# ------------------------------------------------------------
# 7. CREATE INITIAL PROJECT SUMMARY
# ------------------------------------------------------------

summary <- c(
  "NEWS AGGREGATOR PROJECT",
  "=======================",
  "",
  paste("Created:", Sys.Date()),
  paste("Location:", project_dir),
  "",
  "Geographic coverage:",
  "San Antonio, Texas, National, International",
  "",
  "Categories:",
  paste(categories$category, collapse = ", "),
  "",
  "Initialization: COMPLETE"
)

writeLines(summary, "logs/project_initialization.txt")

# ------------------------------------------------------------
# 8. DISPLAY RESULTS
# ------------------------------------------------------------

cat("\n========================================\n")
cat("NEWS AGGREGATOR INITIALIZATION COMPLETE\n")
cat("========================================\n")

cat("\nProject directory:\n")
cat(project_dir, "\n")

cat("\nFolders created:\n")
cat(paste(folders, collapse = "\n"))

cat("\n\nConfiguration files created:\n")
cat("- config/news_categories.csv\n")
cat("- config/news_sources.csv\n")
cat("- R/00_packages.R\n")
cat("- README.md\n")
cat("- .gitignore\n")

cat("\nPhase 1 initialization successful!\n")
