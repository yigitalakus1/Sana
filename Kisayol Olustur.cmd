@echo off
chcp 65001 >nul
title Sana - Kisayol Olustur
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0create_shortcut.ps1" %*
pause
