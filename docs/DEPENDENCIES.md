# Dependencies and environment

The project includes `R/00_packages.R`, which declares:

`shiny`, `bslib`, `tidyverse`, `httr2`, `xml2`, `lubridate`, `tidytext`, `DT`, `janitor`, `here`, `scales`, `plotly`, `stopwords`.

The active `dashboard/app.R` directly checks for `shiny`, `dplyr`, `ggplot2`, and `readr`.

Run from the project root:

```r
source("R/00_packages.R")
shiny::runApp("dashboard", launch.browser = TRUE)
```

To document exact versions from the machine used to run the project:

```r
writeLines(capture.output(sessionInfo()), "session_info.txt")
```

Consider `renv` for package version locking before deployment. The existing Task Scheduler `.bat` references a machine-specific Rscript path; update that path on a new Windows computer.
