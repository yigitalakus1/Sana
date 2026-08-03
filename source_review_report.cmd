@echo off
chcp 65001 >nul
pushd "%~dp0sana-rag-backend"
".venv\Scripts\python.exe" -m tools.source_review_report %*
set "SANA_REPORT_EXIT=%ERRORLEVEL%"
popd
exit /b %SANA_REPORT_EXIT%
