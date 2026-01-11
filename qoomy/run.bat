@echo off
setlocal enabledelayedexpansion

echo === Qoomy Local Run ===
echo.

:: Load environment variables from .env.local
if exist .env.local (
    for /f "tokens=1,2 delims==" %%a in (.env.local) do (
        set "%%a=%%b"
    )
) else (
    echo ERROR: .env.local not found!
    echo Please create .env.local with Firebase API keys.
    exit /b 1
)

:: Build the dart-define arguments
set DART_DEFINES=--dart-define=FIREBASE_WEB_API_KEY=%FIREBASE_WEB_API_KEY%
set DART_DEFINES=%DART_DEFINES% --dart-define=FIREBASE_ANDROID_API_KEY=%FIREBASE_ANDROID_API_KEY%
set DART_DEFINES=%DART_DEFINES% --dart-define=FIREBASE_IOS_API_KEY=%FIREBASE_IOS_API_KEY%

echo Running Flutter with environment variables...
call "C:/flutter/flutter/bin/flutter.bat" run %DART_DEFINES% %*

endlocal
