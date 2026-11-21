@echo off
setlocal

cd /d "C:\Users\vonne\OneDrive\Desktop\news_aggregator"

"C:\PROGRA~1\R\R-45~1.3\bin\x64\Rscript.exe" "run_news_collection.R"

if errorlevel 1 (
    echo News collection failed.
    exit /b 1
)

echo News collection completed successfully.
exit /b 0