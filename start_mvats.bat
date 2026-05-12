REM file header note
@echo off
color 0A
title MVATS System Launcher
echo ==========================================
echo     MVATS - Multi-Modal Video Analysis
echo ==========================================
echo.

echo [1/4] Starting MongoDB...
if not exist "C:\data\logs" mkdir "C:\data\logs"
start "MongoDB" cmd /c "echo MongoDB starting on localhost:27017... && "E:\University\University Software\mongoDB\bin\mongod.exe" --dbpath "C:\data\db" --logpath "C:\data\logs\mongodb.log" --logappend >nul 2>&1"
timeout /t 3 /nobreak >nul
echo       MongoDB started (logs: C:\data\logs\mongodb.log)

echo [2/4] Starting Node.js Backend...
start "Backend" cmd /k "cd /d D:\bia\Backend && npm start"
timeout /t 2 /nobreak >nul

echo [3/4] Starting ML Inference Server...
start "ML Server" cmd /k "cd /d D:\bia\mvats && D:\bia\.venv\Scripts\python.exe inference_server.py"
timeout /t 2 /nobreak >nul

echo [4/4] Starting Flutter App...
start "Flutter" cmd /k "cd /d D:\bia\mvats && flutter run -d windows --no-pub"

echo.
echo ==========================================
echo   All services launched!
echo   MongoDB  : localhost:27017
echo   Backend  : localhost:3000
echo   ML Server: localhost:5000
echo ==========================================
echo.
pause