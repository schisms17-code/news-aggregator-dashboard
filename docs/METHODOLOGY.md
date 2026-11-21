# Collection and archive methodology

## 1. Sources and collection

The feed configuration is maintained in `config/news_sources.csv`, with source name, region, category, URL, and active status. `R/01_collect_news.R` retrieves RSS entries and writes a timestamped RDS snapshot, latest RDS/CSV datasets, and a feed-level log.

## 2. Archive construction

`R/02_build_news_archive.R` loads snapshot files matching `news_snapshot_YYYYMMDD_HHMMSS.rds`. It aligns column names across snapshots and builds a grouping identifier using the first available of `article_key`, `normalized_url`, and `article_url`, with a source-and-title fallback. It retains one row per grouping key, favoring the most recent snapshot, and calculates `first_seen`, `last_seen`, and `snapshots_seen` from snapshot filenames. Results are written as archive RDS and CSV.

## 3. Date repair

`R/03_repair_archive_dates.R` makes a timestamped backup before attempting to recover missing `publication_date_utc` values from `publication_date_raw`, including RFC-style GMT/UTC strings. Existing nonmissing timestamps are preserved. The script checks that row count remains positive and article keys remain unique, then saves updated archive files.

## 4. Automation and validation

`run_news_collection.R` coordinates collection, archive rebuild, repair, and logging. It uses a lock directory to prevent overlapping collection runs and validates latest-file updates, archive row counts, unique article keys, and missing publication dates. A Windows `.bat` file launches it through Rscript under Task Scheduler. The wrapper invokes archive-backup retention with `keep = 10` after repair; cleanup errors are logged as warnings rather than failing the collection.

## 5. Reproducibility and limitations

The workflow depends on external RSS feed availability and a local Windows scheduler configuration. Archived results change over time as snapshots accumulate. Feed metadata may contain missing or incorrect timestamps, syndicated duplicates, and publisher-specific formatting. A snapshot records what a feed returned when polled; it does not provide complete coverage of all articles published between polls.
