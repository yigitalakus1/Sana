@echo off
chcp 65001 >nul
title Sana - Ilk Kurulum
cd /d "%~dp0"

echo.
echo   Sana ilk kurulumu baslatiliyor...
echo   Internet baglantisi model ve paket indirmek icin gereklidir.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_local.ps1" %*

if errorlevel 1 (
  echo.
  echo   Kurulum tamamlanamadi. Yukaridaki hata mesajini kontrol edin.
  echo.
  pause
  exit /b 1
)

echo.
echo   Kurulum tamamlandi.
echo.
pause
