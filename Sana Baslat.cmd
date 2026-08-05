@echo off
chcp 65001 >nul
title Sana
cd /d "%~dp0"

echo.
echo   Sana baslatiliyor...
echo   (Bu pencereyi kapatma; servisler burada calisiyor.)
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_local.ps1" %*

if errorlevel 1 (
  echo.
  echo   Baslatma sirasinda bir sorun olustu.
  echo   Ayrinti icin yukaridaki mesajlara bak.
  echo.
  pause
  exit /b 1
)

echo.
echo   Sana hazir. Tarayici acilmadiysa: http://127.0.0.1:57009
echo.
echo   Kapatmak icin bu pencerede bir tusa bas
echo   (servisler durdurulacak).
echo.
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop_local.ps1"
