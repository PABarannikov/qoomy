@echo off
echo Killing Flutter/Node processes on port 3000...
powershell -Command "Stop-Process -Name 'node' -Force -ErrorAction SilentlyContinue; Stop-Process -Name 'dart' -Force -ErrorAction SilentlyContinue"
timeout /t 2 /nobreak >nul
echo Starting Flutter web server on http://localhost:3000 ...
cd /d C:\Qoomy\qoomy
C:\flutter\flutter\bin\flutter.bat run -d web-server --web-port=3000
