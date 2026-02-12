@echo off
chcp 65001 >nul
title АСУНО E-commerce

echo ========================================
echo   АСУНО E-commerce — LOCAL START
echo ========================================
echo.

cd /d D:\DOM

echo [1/3] Остановка контейнеров...
docker compose down

echo [2/3] Запуск Docker контейнеров (Backend + PostgreSQL)...
docker compose up -d

if errorlevel 1 (
    echo ❌ Ошибка Docker Compose
    pause
    exit /b 1
)

echo ✅ Docker контейнеры запущены
echo.
timeout /t 3 /nobreak

echo [3/3] Запуск Frontend (Vue 3 + Vite)...
start "АСУНО Frontend" cmd /k "cd /d D:\DOM\frontend && npm run dev"

echo.
echo Ждём запуска Frontend (5 сек)...
timeout /t 5 /nobreak

echo.
echo ========================================
echo ✅ ПРИЛОЖЕНИЕ ЗАПУЩЕНО:
echo.
echo   Frontend:  http://localhost:5173
echo   Backend:   http://localhost:8000
echo   API Docs:  http://localhost:8000/docs
echo.
echo ========================================
echo.

REM Открыть браузер
echo Открываю браузер...
start http://localhost:5173

echo.
pause