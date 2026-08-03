@echo off
chcp 65001 >nul
pushd "%~dp0sana-rag-backend"
".venv\Scripts\python.exe" -m tools.evaluate_local_model %*
set "SANA_EVAL_EXIT=%ERRORLEVEL%"
popd
exit /b %SANA_EVAL_EXIT%
