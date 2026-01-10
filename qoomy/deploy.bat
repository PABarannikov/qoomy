@echo off
setlocal

echo === Qoomy Deploy Script ===
echo.

:: Check for uncommitted changes
git diff --quiet HEAD 2>nul
if %errorlevel% neq 0 (
    echo ERROR: You have uncommitted changes!
    echo Please commit your changes before deploying.
    echo.
    git status --short
    exit /b 1
)

:: Check for untracked files
for /f %%i in ('git ls-files --others --exclude-standard') do (
    echo ERROR: You have untracked files!
    echo Please commit or ignore them before deploying.
    echo.
    git status --short
    exit /b 1
)

echo [1/3] Building Flutter web...
call "C:/flutter/flutter/bin/flutter.bat" build web --release
if %errorlevel% neq 0 (
    echo ERROR: Build failed!
    exit /b 1
)

echo.
echo [2/3] Deploying to Firebase...
call firebase deploy --only hosting
if %errorlevel% neq 0 (
    echo ERROR: Deploy failed!
    exit /b 1
)

echo.
echo [3/3] Done!
echo Deployed commit:
git log --oneline -1

endlocal
