
# ============================================================
# NEWS AGGREGATOR
# PHASE 2 - STEP 1
# INITIALIZE RSS NEWS SOURCES
# ============================================================

library(tidyverse)

# Google News RSS URL generator
google_news_url <- function(query) {

  paste0(
    "https://news.google.com/rss/search?q=",
    URLencode(query, reserved = TRUE),
    "&hl=en-US&gl=US&ceid=US:en"
  )

}

# ------------------------------------------------------------
# NEWS SOURCE INVENTORY
# ------------------------------------------------------------

news_sources <- tibble(

  source_name = c(
    "KSAT Local",
    "KSAT Politics",
    "KSAT Crime",
    "KSAT Money",
    "Texas Tribune",
    "Google News San Antonio Government",
    "Google News San Antonio Crime",
    "Google News Texas Politics",
    "Google News US Business",
    "Google News US Technology",
    "Google News US Public Health",
    "Google News US Education",
    "Google News International Politics",
    "Google News International Business",
    "Google News International Health",
    "Google News International Technology"
  ),

  region = c(
    "San Antonio",
    "San Antonio",
    "San Antonio",
    "San Antonio",
    "Texas",
    "San Antonio",
    "San Antonio",
    "Texas",
    "National",
    "National",
    "National",
    "National",
    "International",
    "International",
    "International",
    "International"
  ),

  category = c(
    "Local Government",
    "Politics",
    "Crime & Public Safety",
    "Business & Economy",
    "Politics",
    "Local Government",
    "Crime & Public Safety",
    "Politics",
    "Business & Economy",
    "Technology",
    "Public Health",
    "Education",
    "Politics",
    "Business & Economy",
    "Public Health",
    "Technology"
  ),

  feed_url = c(

    "https://www.ksat.com/arc/outboundfeeds/rss/category/news/local/?outputType=xml&size=10",

    "https://www.ksat.com/arc/outboundfeeds/rss/category/news/politics/?outputType=xml&size=10",

    "https://www.ksat.com/arc/outboundfeeds/rss/tags_slug/crime/?outputType=xml&size=10",

    "https://www.ksat.com/arc/outboundfeeds/rss/category/money/?outputType=xml&size=10",

    "https://feeds.texastribune.org/feeds/main/",

    google_news_url('"San Antonio" government OR city council OR mayor'),

    google_news_url('"San Antonio" crime OR police OR public safety'),

    google_news_url('Texas politics OR Texas legislature OR Texas government'),

    google_news_url('United States business OR economy OR employment'),

    google_news_url('United States technology OR artificial intelligence'),

    google_news_url('"public health" OR healthcare OR CDC'),

    google_news_url('education OR schools OR universities'),

    google_news_url('international politics OR world government'),

    google_news_url('international business OR global economy'),

    google_news_url('international public health OR global health'),

    google_news_url('international technology OR science')
  ),

  active = TRUE

)

# ------------------------------------------------------------
# SAVE SOURCE CONFIGURATION
# ------------------------------------------------------------

write.csv(
  news_sources,
  "config/news_sources.csv",
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

# ------------------------------------------------------------
# DISPLAY RESULTS
# ------------------------------------------------------------

cat("\n====================================\n")
cat("NEWS SOURCE CONFIGURATION COMPLETE\n")
cat("====================================\n")

cat("\nTotal sources:", nrow(news_sources), "\n")

cat("\nSources by region:\n")

print(
  news_sources %>%
    count(region)
)

cat("\nSources by category:\n")

print(
  news_sources %>%
    count(category)
)

cat("\nConfiguration saved successfully.\n")
