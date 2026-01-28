@echo off
setlocal EnableDelayedExpansion

echo === Qoomy Deploy Script ===
echo.

:: Check for .env.local file
if not exist ".env.local" (
    echo ERROR: .env.local file not found!
    echo Please create .env.local with FIREBASE_WEB_API_KEY
    exit /b 1
)

:: Read API key from .env.local
for /f "tokens=1,* delims==" %%a in (.env.local) do (
    if "%%a"=="FIREBASE_WEB_API_KEY" set "FIREBASE_WEB_API_KEY=%%b"
)

if "%FIREBASE_WEB_API_KEY%"=="" (
    echo ERROR: FIREBASE_WEB_API_KEY not found in .env.local!
    exit /b 1
)

:: Check for argument
if "%1"=="--local" goto :local_deploy
if "%1"=="-l" goto :local_deploy

:: Default: Git push and let GitHub Actions deploy
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

echo [1/2] Pushing to git...
git push
if %errorlevel% neq 0 (
    echo ERROR: Git push failed!
    exit /b 1
)

echo.
echo [2/2] Done!
echo Pushed commit:
git log --oneline -1
echo.
echo Firebase deployment will be triggered by GitHub Actions.
goto :end

:local_deploy
echo.
echo === Local Web Deployment ===
echo.

echo [1/3] Building web with API key...
flutter build web --release --dart-define=FIREBASE_WEB_API_KEY=%FIREBASE_WEB_API_KEY%
if %errorlevel% neq 0 (
    echo ERROR: Flutter build failed!
    exit /b 1
)

echo.
echo [2/3] Deploying to Firebase Hosting...
firebase deploy --only hosting
if %errorlevel% neq 0 (
    echo ERROR: Firebase deploy failed!
    exit /b 1
)

echo.
echo [3/3] Done!
echo Web deployed to: https://qoomy-quiz-game.web.app

:end
endlocal
