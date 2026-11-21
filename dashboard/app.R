# NEWS AGGREGATOR DASHBOARD 2.0
# Save as news_aggregator/dashboard/app.R
# Run from project root: shiny::runApp('dashboard', launch.browser = TRUE)

required <- c('shiny', 'dplyr', 'ggplot2', 'readr')
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop('Install packages: install.packages(c(', paste(sprintf('"%s"', missing), collapse = ', '), '))')
library(shiny)
library(dplyr)
library(ggplot2)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

locate_data <- function() {
  paths <- c('data/processed/news_articles_latest.rds', '../data/processed/news_articles_latest.rds',
             'data/processed/news_articles_latest.csv', '../data/processed/news_articles_latest.csv')
  found <- paths[file.exists(paths)]
  if (!length(found)) stop('Cannot locate news_articles_latest.rds. Run the collector first from project root.')
  normalizePath(found[1], winslash = '/', mustWork = TRUE)
}
data_path <- locate_data()
field <- function(x, choices, default = '') {
  found <- choices[choices %in% names(x)]
  if (length(found)) return(as.character(x[[found[1]]]))
  rep(default, nrow(x))
}
parse_dates <- function(x) {
  if (inherits(x, 'POSIXt')) return(as.POSIXct(x, tz = 'UTC'))
  if (inherits(x, 'Date')) return(as.POSIXct(x, tz = 'UTC'))
  if (is.numeric(x)) return(as.POSIXct(x, origin = '1970-01-01', tz = 'UTC'))
  x <- as.character(x)
  suppressWarnings(as.POSIXct(x, tz = 'UTC', tryFormats = c(
    '%Y-%m-%d %H:%M:%OS', '%Y-%m-%dT%H:%M:%OSZ', '%Y-%m-%dT%H:%M:%OS%z',
    '%Y-%m-%d', '%a, %d %b %Y %H:%M:%S %Z', '%a, %d %b %Y %H:%M:%S')))
}
normalize_news <- function(raw) {
  if (!is.data.frame(raw)) stop('News dataset is not a data frame')
  clean <- function(z, default = 'Unknown') { z[is.na(z) | !nzchar(trimws(z))] <- default; z }
  dates_col <- c('publication_date_utc','published_at', 'published', 'pub_date', 'publication_date', 'published_date', 'date')
  dc <- dates_col[dates_col %in% names(raw)]
  dates <- if (length(dc)) parse_dates(raw[[dc[1]]]) else rep(as.POSIXct(NA, tz = 'UTC'), nrow(raw))
  x <- data.frame(
    title = clean(field(raw, c('title','headline','article_title')), 'Untitled article'),
    source = clean(field(raw, c('source','source_name','feed_name','publisher'))),
    region = clean(field(raw, c('source_region','region','geography','location'))),
    category = clean(field(raw, c('source_category','category','topic','section'))),
    url = field(raw, c('link','url','article_url','article_link')),
    description = field(raw, c('article_description','description','summary','snippet','content')),
    published_at = dates, stringsAsFactors = FALSE)
  x$article_id <- seq_len(nrow(x))
  x[order(x$published_at, decreasing = TRUE, na.last = TRUE), , drop = FALSE]
}
read_news <- function(path) {
  raw <- if (grepl('\\.rds$', path, ignore.case = TRUE)) readRDS(path) else readr::read_csv(path, show_col_types = FALSE)
  normalize_news(raw)
}
initial <- read_news(data_path)
valid_days <- as.Date(initial$published_at, tz = 'UTC')
valid_days <- valid_days[!is.na(valid_days)]
date_min <- if (length(valid_days)) min(valid_days) else Sys.Date() - 30
date_max <- if (length(valid_days)) max(valid_days) else Sys.Date()


# The archive is independent of the latest-news snapshot.
archive_path <- file.path(dirname(data_path), 'news_articles_archive.rds')
read_archive <- function(path) {
  if (!file.exists(path)) return(data.frame())
  raw <- readRDS(path)
  x <- normalize_news(raw)
  x$first_seen <- if ('first_seen' %in% names(raw)) parse_dates(raw$first_seen) else as.POSIXct(NA, tz='UTC')
  x$last_seen <- if ('last_seen' %in% names(raw)) parse_dates(raw$last_seen) else as.POSIXct(NA, tz='UTC')
  x$snapshots_seen <- if ('snapshots_seen' %in% names(raw)) as.integer(raw$snapshots_seen) else rep(1L,nrow(raw))
  x
}
archive_initial <- read_archive(archive_path)
archive_regions <- if (nrow(archive_initial)) sort(unique(archive_initial$region)) else character()
archive_categories <- if (nrow(archive_initial)) sort(unique(archive_initial$category)) else character()

# Transparent, deterministic text analysis; no external NLP service required.
stopwords <- c('the','and','for','with','from','that','this','into','after','over','under','about',
 'amid','says','say','said','will','are','was','were','has','have','had','its','their','they',
 'but','not','you','your','his','her','our','new','more','than','who','what','when','where',
 'why','how','all','can','may','could','would','should','one','two','three','out','off','get',
 'gets','got','just','also','today','latest','news','live','update','updates','report','reports',
 'year','years','day','days','week','weeks','city','state','states','us','usa','via','s',
 'a','an','of','to','in','on','at','by','as','is','it','be','or','if','do','did','so')
words <- function(x) {
  x <- tolower(iconv(paste(x, collapse = ' '), to = 'ASCII//TRANSLIT', sub = ''))
  x <- gsub('[^a-z0-9 ]', ' ', x)
  w <- unlist(strsplit(x, '[[:space:]]+'), use.names = FALSE)
  unique(w[nchar(w) >= 3 & !(w %in% stopwords) & !grepl('^[0-9]+$', w)])
}
trending <- function(x, n = 25) {
  if (!nrow(x)) return(data.frame(keyword = character(), articles = integer()))
  tokens <- lapply(x$title, words)
  tab <- sort(table(unlist(tokens, use.names = FALSE)), decreasing = TRUE)
  head(data.frame(keyword = names(tab), articles = as.integer(tab), row.names = NULL), n)
}
# Duplicate candidates are approximate: headlines with >= 70% Jaccard token overlap.
# Each group is built greedily, and similarity is measured against the group's first title.
find_duplicates <- function(x, threshold = .70) {
  if (!nrow(x)) return(data.frame())
  token_sets <- lapply(x$title, words)
  group <- integer(nrow(x)); leaders <- integer()
  for (i in seq_len(nrow(x))) {
    if (length(token_sets[[i]]) < 3) next
    matched <- FALSE
    for (j in leaders) {
      a <- token_sets[[i]]; b <- token_sets[[j]]
      sim <- length(intersect(a, b)) / length(union(a, b))
      if (is.finite(sim) && sim >= threshold) {
        group[i] <- group[j]; matched <- TRUE; break
      }
    }
    if (!matched) { leaders <- c(leaders, i); group[i] <- length(leaders) }
  }
  counts <- table(group[group > 0])
  kept <- which(group > 0 & group %in% as.integer(names(counts[counts > 1])))
  if (!length(kept)) {
    out <- x[FALSE, c('title','source','region','category','published_at','url'), drop = FALSE]
    out$group <- integer(0)
    return(out[, c('group','title','source','region','category','published_at','url'), drop = FALSE])
  }
  out <- x[kept, c('title','source','region','category','published_at','url'), drop = FALSE]
  out$group <- group[kept]
  out <- out[, c('group','title','source','region','category','published_at','url')]
  out[order(out$group, out$published_at, decreasing = FALSE, na.last = TRUE), , drop = FALSE]
}

fmt_date <- function(z) if (length(z) == 0 || is.na(z)) 'Unknown date' else format(z, '%b %d, %Y %I:%M %p UTC', tz = 'UTC')
metric <- function(label, value) tags$div(class='metric', tags$div(class='metric-label',label), tags$div(class='metric-value',as.character(value)))
article_card <- function(x) {
  link <- if (length(x$url) && !is.na(x$url[1]) && grepl('^https?://', x$url[1], ignore.case=TRUE)) x$url[1] else NULL
  tags$div(class='article', tags$div(class='meta', paste(x$source[1], ' • ', x$region[1], ' • ', x$category[1])),
    tags$h4(if (is.null(link)) x$title[1] else tags$a(x$title[1], href=link, target='_blank', rel='noopener noreferrer')),
    if (nzchar(x$description[1])) tags$p(substr(x$description[1], 1, 350)) else NULL,
    tags$div(class='meta', fmt_date(x$published_at[1])))
}
css <- '
body {background:#f3f6fa; color:#20334b; font-family:system-ui,"Segoe UI",sans-serif;}
.navbar {background:#153451!important; border:0; border-radius:0;}
.navbar-default .navbar-brand,.navbar-default .navbar-nav>li>a {color:white!important;}
.navbar-default .navbar-nav>.active>a {background:#285579!important; color:white!important;}
.container-fluid {max-width:1500px;}
.page-head {margin:25px 0 18px;} .page-head h2 {font-weight:750;color:#153451;}
.page-head p,.meta {color:#667b91;}
.metrics {display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin:18px 0 22px;}
.metric,.panel,.article {background:white;border:1px solid #e1e8ef;border-radius:12px;padding:18px;margin-bottom:14px;}
.metric-label {font-size:13px;color:#667b91;} .metric-value {font-size:29px;font-weight:750;color:#173d63;}
.panel h3 {font-size:19px;color:#173d63;margin-top:0;} .article h4 {line-height:1.4;font-weight:700;}
.article p {color:#46596c;} .meta {font-size:12px;} .note {color:#65778a;font-size:13px;}
@media(max-width:950px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr));}}
@media(max-width:550px){.metrics{grid-template-columns:1fr;}}
'
header <- function(title, subtitle) tags$div(class='page-head', tags$h2(title), tags$p(subtitle))
plot_theme <- function() theme_minimal(base_size=12) + theme(panel.grid.minor=element_blank(), axis.title.y=element_blank())
bar_plot <- function(x, col, top=15) {
  if (!nrow(x)) return(ggplot() + theme_void())
  counts <- sort(table(x[[col]]), decreasing=TRUE)
  counts <- head(counts, top)
  d <- data.frame(label=names(counts), count=as.integer(counts))
  ggplot(d, aes(x=reorder(label,count),y=count)) + geom_col(fill='#2a6c94') + coord_flip() +
    labs(x=NULL,y='Articles') + plot_theme()
}

ui <- navbarPage('NEWS AGGREGATOR 3.0', id='nav', header=tags$head(tags$style(htmltools::HTML(css))),
  tabPanel('Home', header('News Intelligence Dashboard','Live view of the latest locally saved RSS snapshot'),
    uiOutput('metrics'), div(class='panel',h3('Latest headlines'),uiOutput('latest')),
    div(class='panel',h3('Top trending keywords'),plotOutput('home_trends',height='310px'))),
  tabPanel('Explore News', header('Explore News','Search and filter saved articles'),
    div(class='panel',fluidRow(
      column(4,textInput('search','Search headlines or descriptions')),
      column(2,selectInput('region','Region',choices=c('All',sort(unique(initial$region))))),
      column(3,selectInput('category','Category',choices=c('All',sort(unique(initial$category))))),
      column(3,selectInput('source','Source',choices=c('All',sort(unique(initial$source)))))),
      fluidRow(column(6,dateRangeInput('date_range','Published between',start=date_min,end=date_max)),
               column(3,selectInput('page_size','Articles per page',c(10,20,50),selected=20)),
               column(3,br(),actionButton('reset','Reset filters')))),
    div(class='panel',fluidRow(column(8,h3(textOutput('match_count',inline=TRUE))),
                               column(4,downloadButton('download','Export filtered CSV'))),
        uiOutput('results'),actionButton('prev','Previous'),textOutput('page_status',inline=TRUE),actionButton('next_page','Next'))),
  tabPanel('News Analytics',header('News Analytics','Descriptive trends from collected RSS feeds'),
    uiOutput('analytics_metrics'),
    fluidRow(column(6,div(class='panel',h3('By region'),plotOutput('region_plot',height='320px'))),
             column(6,div(class='panel',h3('By category'),plotOutput('category_plot',height='320px')))),
    fluidRow(column(6,div(class='panel',h3('By source'),plotOutput('source_plot',height='360px'))),
             column(6,div(class='panel',h3('Daily publication volume'),plotOutput('daily_plot',height='360px')))),
    div(class='panel',h3('Region × category'),tableOutput('coverage_table'))),
  tabPanel('Trending Topics',header('Trending Topics','Keywords appearing in the greatest number of article titles'),
    div(class='panel',fluidRow(column(4,selectInput('trend_region','Region',c('All',sort(unique(initial$region))))),
                              column(4,numericInput('trend_days','Lookback days (relative to latest article)',7,min=1,max=365)),
                              column(4,downloadButton('trend_download','Export keywords'))),
        tags$p(class='note','Each keyword is counted once per headline. High frequency does not necessarily indicate an emerging trend.'),
        plotOutput('trend_plot',height='470px'),tableOutput('trend_table'))),
  tabPanel('Similar Stories',header('Similar Stories','Potential duplicate coverage identified by headline similarity'),
    div(class='panel',sliderInput('similarity','Minimum headline similarity',min=.50,max=1,value=.70,step=.05),
        tags$p(class='note','Greedy headline-token matching. These are candidate duplicates, not verified identical stories.'),
        uiOutput('duplicate_summary'),downloadButton('duplicate_download','Export matches'),
        tableOutput('duplicate_table'))),
  tabPanel('News Monitor',header('News Monitor','Monitor subjects across all regions and news sources'),
    div(class='panel',textInput('monitor_terms','Keywords (comma-separated)','San Antonio, Texas, city council, public health, crime'),
        tags$p(class='note','A match is any case-insensitive literal keyword or phrase in a headline or description.'),
        uiOutput('monitor_metrics'),plotOutput('monitor_plot',height='330px'),
        downloadButton('monitor_download','Export monitored articles'),uiOutput('monitor_articles'))),

  tabPanel('Historical Trends',header('Historical News Trends','Unique archived articles by publication date; not collection volume'),
    uiOutput('archive_metrics'),
    div(class='panel',fluidRow(column(4,selectInput('hist_region','Region',c('All',archive_regions))),
      column(4,selectInput('hist_category','Category',c('All',archive_categories))),
      column(4,selectInput('hist_granularity','Group by',c('Day','Week','Month')))),
      plotOutput('hist_timeline',height='380px'),
      tags$p(class='note','Counts are unique articles by publication date. Missing publication dates are excluded from the timeline.')),
    fluidRow(column(6,div(class='panel',h3('Historical region coverage'),plotOutput('hist_regions_plot',height='330px'))),
      column(6,div(class='panel',h3('Historical category coverage'),plotOutput('hist_categories_plot',height='330px'))))),
  tabPanel('Article Persistence',header('Article Persistence','Repeated appearances in saved RSS snapshots'),
    div(class='panel',uiOutput('persistence_metrics'),
      tags$p(class='note','First/last seen are snapshot observation times (UTC), not article publication times. Repeated snapshots do not mean independent publishers.'),
      plotOutput('persistence_plot',height='350px'),
      tableOutput('persistence_table'))),
  tabPanel('Archive Explorer',header('Archive Explorer','Search the deduplicated historical database'),
    div(class='panel',fluidRow(column(5,textInput('archive_search','Search headlines or descriptions')),
      column(3,selectInput('archive_region','Region',c('All',archive_regions))),
      column(4,selectInput('archive_category','Category',c('All',archive_categories)))),
      fluidRow(column(8,uiOutput('archive_count')),column(4,downloadButton('archive_export','Export filtered archive'))),
      uiOutput('archive_results'))),
  tabPanel('About',header('About the Project','Collection, methodology and refresh behavior'),
    div(class='panel',h3('Latest snapshot'),tags$code(data_path),h3('Historical archive'),tags$code(archive_path),
        p('The dashboard checks the saved dataset every 60 seconds and reloads it when the file changes.'),
        p('Refreshing the dashboard does not collect RSS feeds. Run the collector manually or schedule it separately.'),
        h3('Methods'),p('Trending keywords are counted by unique article title. Similar stories use Jaccard overlap of normalized title words; this is an approximate screening method.'),
        p('RSS feed coverage is selective. Counts describe collected feed items, not all published news.'),
        h3('Loaded snapshot'),textOutput('snapshot_status')))
)

server <- function(input, output, session) {

  archive_data <- reactiveFileReader(60000, session, archive_path, read_archive)
  historical <- reactive(archive_data())
  observeEvent(historical(), {
    x <- historical()
    for (id in c('hist_region','archive_region')) updateSelectInput(session,id,choices=c('All',sort(unique(x$region))),selected='All')
    for (id in c('hist_category','archive_category')) updateSelectInput(session,id,choices=c('All',sort(unique(x$category))),selected='All')
  }, ignoreInit=TRUE)
  historical_filtered <- reactive({
    x <- historical()
    if (!nrow(x)) return(x)
    if (!is.null(input$hist_region) && input$hist_region != 'All') x <- x[x$region == input$hist_region,,drop=FALSE]
    if (!is.null(input$hist_category) && input$hist_category != 'All') x <- x[x$category == input$hist_category,,drop=FALSE]
    x
  })
  output$archive_metrics <- renderUI({
    x <- historical(); d <- as.Date(x$published_at,tz='UTC')
    tags$div(class='metrics',metric('Unique archived articles',format(nrow(x),big.mark=',')),
      metric('Regions',length(unique(x$region))),metric('Sources',length(unique(x$source))),
      metric('Publication days',length(unique(d[!is.na(d)]))))
  })
  output$hist_timeline <- renderPlot({
    x <- historical_filtered()
    d <- as.Date(x$published_at,tz='UTC'); d <- d[!is.na(d)]
    validate(need(length(d)>0,'No dated articles match the selected filters.'))
    mode <- input$hist_granularity %||% 'Day'
    if (mode == 'Week') d <- as.Date(cut(d,breaks='week'))
    if (mode == 'Month') d <- as.Date(format(d,'%Y-%m-01'))
    t <- as.data.frame(table(d),stringsAsFactors=FALSE)
    t$day <- as.Date(t$d); t$n <- as.integer(t$Freq)
    ggplot(t,aes(day,n)) + geom_col(fill='#2a6c94') + labs(x='Publication period',y='Unique articles') + plot_theme()
  })
  output$hist_regions_plot <- renderPlot(bar_plot(historical(),'region',20))
  output$hist_categories_plot <- renderPlot(bar_plot(historical(),'category',20))
  output$persistence_metrics <- renderUI({
    x <- historical(); seen <- x$snapshots_seen
    tags$div(class='metrics',metric('Unique articles',format(nrow(x),big.mark=',')),
      metric('Seen in 2+ snapshots',sum(seen>=2,na.rm=TRUE)),
      metric('Maximum snapshots',if(length(seen)&&any(!is.na(seen))) max(seen,na.rm=TRUE) else 0),
      metric('Observed on multiple days',sum(as.Date(x$first_seen,tz='UTC') < as.Date(x$last_seen,tz='UTC'),na.rm=TRUE)))
  })
  output$persistence_plot <- renderPlot({
    x <- historical(); z <- x$snapshots_seen; z <- z[!is.na(z)]
    validate(need(length(z)>0,'No persistence data available.'))
    d <- as.data.frame(table(z),stringsAsFactors=FALSE)
    names(d) <- c('snapshots','articles'); d$articles <- as.integer(d$articles)
    ggplot(d,aes(snapshots,articles)) + geom_col(fill='#2a6c94') + labs(x='Distinct snapshots containing article',y='Unique articles') + plot_theme()
  })
  output$persistence_table <- renderTable({
    x <- historical(); if(!nrow(x)) return(data.frame())
    x <- x[order(x$snapshots_seen,decreasing=TRUE,na.last=TRUE),,drop=FALSE]
    head(data.frame(Title=x$title,Source=x$source,Snapshots=x$snapshots_seen,
      First_seen_UTC=format(x$first_seen,'%Y-%m-%d %H:%M',tz='UTC'),
      Last_seen_UTC=format(x$last_seen,'%Y-%m-%d %H:%M',tz='UTC')),30)
  },striped=TRUE)
  archive_filtered <- reactive({
    x <- historical(); if (!nrow(x)) return(x)
    q <- trimws(input$archive_search %||% '')
    if (nzchar(q)) x <- x[grepl(q,x$title,fixed=TRUE,ignore.case=TRUE)|grepl(q,x$description,fixed=TRUE,ignore.case=TRUE),,drop=FALSE]
    if (!is.null(input$archive_region) && input$archive_region != 'All') x <- x[x$region==input$archive_region,,drop=FALSE]
    if (!is.null(input$archive_category) && input$archive_category != 'All') x <- x[x$category==input$archive_category,,drop=FALSE]
    x
  })
  output$archive_count <- renderUI(tags$h4(paste(format(nrow(archive_filtered()),big.mark=','),'matching archived articles')))
  output$archive_results <- renderUI({
    x <- head(archive_filtered(),30)
    if (!nrow(x)) return(tags$p('No matching archived articles. Run the archive builder if the archive is missing.'))
    do.call(tagList,lapply(seq_len(nrow(x)),function(i) article_card(x[i,,drop=FALSE])))
  })
  output$archive_export <- downloadHandler(filename=function() paste0('news_archive_filtered_',Sys.Date(),'.csv'),
    content=function(file) readr::write_csv(archive_filtered(),file))

  # reactiveFileReader watches mtime and loads changed snapshots without restarting Shiny.
  news_data <- reactiveFileReader(60000, session, data_path, read_news)
  news <- reactive(news_data())
  observeEvent(news(), {
    x <- news()
    updateSelectInput(session,'region',choices=c('All',sort(unique(x$region))))
    updateSelectInput(session,'category',choices=c('All',sort(unique(x$category))))
    updateSelectInput(session,'source',choices=c('All',sort(unique(x$source))))
    updateSelectInput(session,'trend_region',choices=c('All',sort(unique(x$region))))
    dates <- as.Date(x$published_at,tz='UTC'); dates <- dates[!is.na(dates)]
    if(length(dates)) updateDateRangeInput(session,'date_range',start=min(dates),end=max(dates),min=min(dates),max=max(dates))
  }, ignoreInit=TRUE)
  output$metrics <- renderUI({
    x <- news(); tags$div(class='metrics',metric('Articles',format(nrow(x),big.mark=',')),
      metric('Sources',length(unique(x$source))),metric('Regions',length(unique(x$region))),
      metric('Categories',length(unique(x$category))))
  })
  output$latest <- renderUI({
    x <- head(news(),12); if(!nrow(x)) return(p('No articles available'))
    do.call(tagList,lapply(seq_len(nrow(x)),function(i) article_card(x[i,,drop=FALSE])))
  })
  output$home_trends <- renderPlot({
    t <- trending(news(),12); if(!nrow(t)) return(ggplot()+theme_void())
    ggplot(t,aes(x=reorder(keyword,articles),y=articles)) + geom_col(fill='#2a6c94')+
      coord_flip()+labs(x=NULL,y='Headlines mentioning keyword')+plot_theme()
  })
  observeEvent(input$reset,{
    updateTextInput(session,'search',value='')
    updateSelectInput(session,'region',selected='All');updateSelectInput(session,'category',selected='All')
    updateSelectInput(session,'source',selected='All')
    x <- as.Date(news()$published_at,tz='UTC'); x <- x[!is.na(x)]
    if(length(x)) updateDateRangeInput(session,'date_range',start=min(x),end=max(x))
  })
  filtered <- reactive({
    x <- news()
    if(!is.null(input$search) && nzchar(trimws(input$search))) {
      q <- trimws(input$search)
      x <- x[grepl(q,x$title,fixed=TRUE,ignore.case=TRUE)|grepl(q,x$description,fixed=TRUE,ignore.case=TRUE),,drop=FALSE]
    }
    for(nm in c('region','category','source')) {
      val <- input[[nm]]
      if(!is.null(val) && val!='All') x <- x[x[[nm]]==val,,drop=FALSE]
    }
    if(length(input$date_range)==2 && all(!is.na(input$date_range))) {
      d <- as.Date(x$published_at,tz='UTC')
      x <- x[!is.na(d)&d>=input$date_range[1]&d<=input$date_range[2],,drop=FALSE]
    }
    x
  })
  page <- reactiveVal(1L)
  observeEvent(list(input$search,input$region,input$category,input$source,input$date_range,input$page_size),page(1L),ignoreInit=TRUE)
  page_size <- reactive({z<-suppressWarnings(as.integer(input$page_size));if(length(z)!=1||is.na(z)||z<1) 20L else z})
  pages <- reactive(max(1L,ceiling(nrow(filtered())/page_size())))
  observeEvent(input$prev,page(max(1L,page()-1L)))
  observeEvent(input$next_page, page(min(pages(), page() + 1L)))
  output$match_count <- renderText(paste(format(nrow(filtered()),big.mark=','),'matching articles'))
  output$page_status <- renderText(paste('Page',min(page(),pages()),'of',pages()))
  output$results <- renderUI({
    x <- filtered();if(!nrow(x)) return(p('No matching articles'))
    a <- (min(page(),pages())-1L)*page_size()+1L;b <- min(nrow(x),a+page_size()-1L)
    do.call(tagList,lapply(seq.int(a,b),function(i) article_card(x[i,,drop=FALSE])))
  })
  output$download <- downloadHandler(filename=function() paste0('news_filtered_',Sys.Date(),'.csv'),
    content=function(file) readr::write_csv(filtered(),file))
  output$analytics_metrics <- renderUI({
    x<-news();d<-as.Date(x$published_at,tz='UTC');d<-d[!is.na(d)]
    tags$div(class='metrics',metric('Total articles',nrow(x)),metric('Dated articles',length(d)),
      metric('Sources',length(unique(x$source))),metric('Coverage days',length(unique(d))))
  })
  output$region_plot <- renderPlot(bar_plot(news(),'region'))
  output$category_plot <- renderPlot(bar_plot(news(),'category'))
  output$source_plot <- renderPlot(bar_plot(news(),'source',16))
  output$daily_plot <- renderPlot({
    x<-news();d<-as.Date(x$published_at,tz='UTC');d<-d[!is.na(d)]
    if(!length(d)) return(ggplot()+theme_void())
    t<-as.data.frame(table(d),stringsAsFactors=FALSE)
    t$day<-as.Date(t$d);t$n<-as.integer(t$Freq)
    ggplot(t,aes(day,n))+geom_line(color='#2a6c94')+geom_point(color='#2a6c94')+
      labs(x='Publication date',y='Articles')+plot_theme()
  })
  output$coverage_table <- renderTable({
    x <- news()
    counts <- sort(table(paste(x$region, x$category, sep = ' | ')), decreasing = TRUE)
    result <- data.frame(coverage = names(counts), articles = as.integer(counts))
    names(result) <- c('Region and category', 'Articles')
    result
  }, striped = TRUE)
  trend_news <- reactive({
    x<-news()
    if(!is.null(input$trend_region)&&input$trend_region!='All') x<-x[x$region==input$trend_region,,drop=FALSE]
    d<-as.Date(x$published_at,tz='UTC');all_d<-as.Date(news()$published_at,tz='UTC');all_d<-all_d[!is.na(all_d)]
    if(length(all_d)) x<-x[!is.na(d)&d>=max(all_d)-as.integer(input$trend_days %||% 7)+1,,drop=FALSE]
    x
  })
  `%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a[1])) b else a
  trend_table <- reactive(trending(trend_news(),50))
  output$trend_plot <- renderPlot({
    x<-head(trend_table(),20);if(!nrow(x)) return(ggplot()+theme_void())
    ggplot(x,aes(reorder(keyword,articles),articles))+geom_col(fill='#2a6c94')+coord_flip()+
      labs(x=NULL,y='Headlines')+plot_theme()
  })
  output$trend_table <- renderTable(trend_table(),striped=TRUE)
  output$trend_download <- downloadHandler(filename=function() paste0('trending_keywords_',Sys.Date(),'.csv'),
    content=function(file) readr::write_csv(trend_table(),file))
  duplicate_data <- reactive(find_duplicates(news(),input$similarity %||% .70))
  output$duplicate_summary <- renderUI({
    x <- duplicate_data()
    group_count <- if ('group' %in% names(x)) length(unique(x$group)) else 0L
    tags$p(paste(nrow(x), 'articles in', group_count, 'potential similar-story groups'))
  })
  output$duplicate_table <- renderTable(head(duplicate_data(),100),striped=TRUE)
  output$duplicate_download <- downloadHandler(filename=function() paste0('similar_stories_',Sys.Date(),'.csv'),
    content=function(file) readr::write_csv(duplicate_data(),file))
  monitor_data <- reactive({
    x<-news();q<-trimws(unlist(strsplit(input$monitor_terms %||% '',',',fixed=TRUE)))
    q<-q[nzchar(q)];if(!length(q)) return(x[FALSE,,drop=FALSE])
    hit<-rep(FALSE,nrow(x))
    for (term in q) {
      title_hit <- grepl(term, x$title, ignore.case = TRUE, fixed = TRUE)
      description_hit <- grepl(term, x$description, ignore.case = TRUE, fixed = TRUE)
      hit <- hit | title_hit | description_hit
    }
    x[hit,,drop=FALSE]
  })
  output$monitor_metrics <- renderUI({
    x<-monitor_data();tags$div(class='metrics',metric('Matching articles',nrow(x)),
      metric('Matching sources',length(unique(x$source))),metric('Regions',length(unique(x$region))),
      metric('Categories',length(unique(x$category))))
  })
  output$monitor_plot <- renderPlot(bar_plot(monitor_data(),'category',12))
  output$monitor_articles <- renderUI({
    x<-head(monitor_data(),20);if(!nrow(x)) return(p('No matching articles'))
    do.call(tagList,lapply(seq_len(nrow(x)),function(i) article_card(x[i,,drop=FALSE])))
  })
  output$monitor_download <- downloadHandler(filename=function() paste0('monitored_news_',Sys.Date(),'.csv'),
    content=function(file) readr::write_csv(monitor_data(),file))
  output$snapshot_status <- renderText({
    x<-news();paste('Loaded',nrow(x),'articles. File modified:',format(file.info(data_path)$mtime,'%Y-%m-%d %H:%M:%S'))
  })
}
shinyApp(ui,server)
