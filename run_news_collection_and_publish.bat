@echo off
setlocal

cd /d "C:\Users\vonne\OneDrive\Desktop\news_aggregator"
if errorlevel 1 exit /b 1

echo ==========================================
echo NEWS AGGREGATOR 3.0 AUTOMATED PIPELINE
echo ==========================================

echo STEP 1: Running news collection...

call "%~dp0run_news_collection.bat"

if errorlevel 1 (
    echo ERROR: News collection failed.
    echo Cloud publishing cancelled.
    exit /b 1
)

echo.
echo STEP 2: Publishing updated news dashboard...

"C:\PROGRA~1\R\R-45~1.3\bin\x64\Rscript.exe" "R\05_run_cloud_publish.R"

if errorlevel 1 (
    echo ERROR: Cloud publishing failed.
    exit /b 1
)

echo.
echo ==========================================
echo PIPELINE COMPLETED SUCCESSFULLY
echo ==========================================

exit /b 0
