# NEWS AGGREGATOR - REQUIRED PACKAGES

required_packages <- c(
  "shiny",
  "bslib",
  "tidyverse",
  "httr2",
  "xml2",
  "lubridate",
  "tidytext",
  "DT",
  "janitor",
  "here",
  "scales",
  "plotly",
  "stopwords"
)

installed <- rownames(installed.packages())

missing_packages <- setdiff(
  required_packages,
  installed
)

if (length(missing_packages) > 0) {
  install.packages(missing_packages)
}

cat('\nPackage verification complete.\n')

for (pkg in required_packages) {
  cat(pkg, ': ',
      ifelse(requireNamespace(pkg, quietly = TRUE),
             'INSTALLED', 'MISSING'), '\n')
}
