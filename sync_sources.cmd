@echo off
chcp 65001 >nul
pushd "%~dp0sana-rag-backend"
".venv\Scripts\python.exe" -m tools.sync_medlineplus --db-path data\sana_rag.db %*
set "SANA_SYNC_EXIT=%ERRORLEVEL%"
popd
exit /b %SANA_SYNC_EXIT%
