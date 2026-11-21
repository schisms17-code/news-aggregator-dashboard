# Historical archive data dictionary

The following columns were inspected in `data/processed/news_articles_archive.csv` in the uploaded project. Data types may differ between CSV and RDS representations.

| Field | Meaning |
|---|---|
| `article_title` | Headline/title supplied by the RSS feed. |
| `article_description` | Feed-provided article summary or description. |
| `article_url` | Original article URL from the feed. |
| `publication_date_raw` | Original publication-date string from the RSS entry. |
| `publication_date_utc` | Parsed publication timestamp, normalized to UTC when possible. |
| `article_guid` | Feed-provided item identifier, when present. |
| `source_name` | Configured name of the news source/feed. |
| `source_region` | Configured geographic region. |
| `source_category` | Configured topic category. |
| `feed_url` | URL of the RSS feed used for collection. |
| `collected_at_utc` | Timestamp associated with ingestion/collection. |
| `normalized_url` | URL normalized for consistent comparison. |
| `article_key` | Article identifier used for deduplication and validation. |
| `article_domain` | Domain associated with the article URL. |
| `first_seen` | Earliest snapshot time containing the article. |
| `last_seen` | Latest snapshot time containing the article. |
| `snapshots_seen` | Count of distinct snapshot files in which the article appeared. |

## Interpretation cautions

- `first_seen` is not the original publication date.
- `last_seen` is not necessarily an update to the underlying article.
- `snapshots_seen` counts collection observations, not user engagement.
- Source categories reflect configuration rather than a validated text classification model.
