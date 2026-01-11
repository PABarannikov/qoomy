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

endlocal
