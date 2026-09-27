@echo off
rem Запуск приложения на Windows. Просто дважды кликните по этому файлу.
rem Приложение работает на процессоре (faster-whisper) — видеокарта не нужна.
chcp 65001 >nul
cd /d "%~dp0"

rem Русский вывод в консоли и офлайн-режим (в сеть ходим только за моделью)
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
set HF_HUB_OFFLINE=1

if exist ".venv\Scripts\python.exe" (
  set "PY=.venv\Scripts\python.exe"
) else (
  set "PY=python"
)

echo ==================================================
echo   Whisper - офлайн-транскрибация
echo ==================================================
echo.
echo Запускаю. Окно браузера откроется само.
echo Это окно не закрывайте, пока идёт работа.
echo.

"%PY%" server.py

echo.
echo Приложение остановлено.
pause
