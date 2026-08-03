@echo off
chcp 65001 >nul
pushd "%~dp0sana-rag-backend"
".venv\Scripts\python.exe" -m tools.review_sources --db-path data\sana_rag.db %*
set "SANA_REVIEW_EXIT=%ERRORLEVEL%"
popd
exit /b %SANA_REVIEW_EXIT%
