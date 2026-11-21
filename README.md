# News Aggregator Dashboard 3.0

**Automated RSS collection, historical archiving, and interactive news analytics in R**

## Overview

This project collects publicly available RSS news metadata across San Antonio, Texas, the United States, and international topics. An R-based pipeline stores timestamped collection snapshots, rebuilds a deduplicated historical archive, repairs missing publication timestamps, and supports exploration in an interactive Shiny dashboard.

The project demonstrates data ingestion, repeatable ETL, data-quality checks, scheduled execution, and analytical application development.

## Features

- RSS ingestion from 16 configured news feeds (see `config/news_sources.csv`).
- Local hourly scheduling through Windows Task Scheduler and `run_news_collection.bat`.
- Timestamped RDS snapshots and latest-collection RDS/CSV outputs.
- Historical archive deduplicated using article identifiers, with `first_seen`, `last_seen`, and `snapshots_seen` metadata.
- Publication-date recovery from raw RSS date strings.
- Automated retention of the 10 most recent archive-repair backups.
- Per-feed collection logs and scheduler execution logs.
- Interactive dashboard with 10 tabs: Home, Explore News, News Analytics, Trending Topics, Similar Stories, News Monitor, Historical Trends, Article Persistence, Archive Explorer, and About.

## Architecture

```text
RSS feeds (config/news_sources.csv)
            |
            v
R/01_collect_news.R
            |--> data/raw/news_snapshot_*.rds
            |--> data/processed/news_articles_latest.{rds,csv}
            |--> logs/feed_log_*.csv
            v
R/02_build_news_archive.R
            |--> data/processed/news_articles_archive.{rds,csv}
            v
R/03_repair_archive_dates.R
            |--> date repair + timestamped archive backup
            v
run_news_collection.R
            |--> validations + backup retention + scheduler logs
            v
dashboard/app.R (Shiny)
```

The scheduler wrapper orchestrates collection, archive rebuilding, repair, and validation. The Shiny dashboard reads locally stored processed files; the app is **not** automatically hosted online.

## Getting started

1. Install R and RStudio.
2. Install the packages required by the project (see `R/00_packages.R` and `docs/DEPENDENCIES.md`).
3. From RStudio, set the working directory to the cloned repository.
4. Run the collector once to generate local data, or provide valid existing processed data files.
5. Launch the dashboard:

```r
setwd("PATH/TO/news_aggregator")
source("R/00_packages.R")
source("R/01_collect_news.R")
collect_all_news()
source("R/02_build_news_archive.R")
build_news_archive(project_dir = getwd())
source("R/03_repair_archive_dates.R")
repair_archive_dates()
shiny::runApp("dashboard", launch.browser = TRUE)
```

**Windows scheduler note:** The included `run_news_collection.R` and `.bat` contain machine-specific paths. Update them for your computer before enabling Task Scheduler. Do not run multiple collectors concurrently.

**Data note:** Collected article metadata is stored locally and is excluded from the recommended public repository configuration. The app requires generated processed data to run.

## Data model and methodology

See [Data dictionary](docs/DATA_DICTIONARY.md) and [Methodology](docs/METHODOLOGY.md) for field definitions, deduplication, date handling, and limitations.

## Quality checks

The scheduled wrapper verifies that the latest dataset is updated, the archive is nonempty, repaired archive row counts remain unchanged, and article keys are unique. It logs any remaining missing publication dates. Retention cleanup is attempted after the main pipeline completes.

**Verified local example (November 21, 2026, 9:31 AM scheduled run):** 12 snapshots loaded, 10,239 snapshot rows, 1,817 unique archived articles, 265 historical publication dates recovered, zero remaining missing publication dates, and `Collection succeeded.` in the log. These are a historical run's results, not live dashboard counts.

## Limitations

- RSS coverage is selective and dependent on publisher feed availability, feed ordering, and syndication.
- Publication dates reflect feed metadata; they are not independently fact-checked.
- Deduplication depends on article identifiers/URLs and may not merge every syndicated or rewritten story.
- `snapshots_seen` measures appearances in collected snapshots, not readership or article popularity.
- Local Task Scheduler only runs while the configured Windows environment permits execution.
- Hosted deployment requires a plan to supply and refresh processed datasets; local hourly updates do not automatically sync to a remote server.

## Responsible use

This project analyzes RSS article metadata and links to publishers; it does not claim ownership of third-party news content. Check publisher terms and attribution requirements before redistributing collected records.

## Project status

Local data collection, hourly scheduler repetition, archive building, date recovery, and dashboard functionality have been tested. Backup retention passed a dry-run test; automatic execution of retention awaits confirmation in a subsequent scheduler log. Online hosting has not yet been configured.

## Author

Michael Serna
