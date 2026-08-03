@echo off
chcp 65001 >nul
pushd "%~dp0sana-rag-backend"
".venv\Scripts\python.exe" -m tools.generate_source_draft --db-path data\sana_rag.db %*
set "SANA_DRAFT_EXIT=%ERRORLEVEL%"
popd
exit /b %SANA_DRAFT_EXIT%
