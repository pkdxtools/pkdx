@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "CACHE_DIR=%LOCALAPPDATA%\pkdx"
set "BINARY_NAME=pkdx-windows-x86_64.exe"
set "BINARY=%CACHE_DIR%\%BINARY_NAME%"

rem Check local build first
set "LOCAL_BUILD=%REPO_ROOT%\pkdx\_build\native\release\build\src\main\main.exe"
set "LOCAL_BUILD_DEBUG=%REPO_ROOT%\pkdx\_build\native\debug\build\src\main\main.exe"
if exist "%LOCAL_BUILD%" (
  "%LOCAL_BUILD%" %*
  exit /b %ERRORLEVEL%
)
if exist "%LOCAL_BUILD_DEBUG%" (
  "%LOCAL_BUILD_DEBUG%" %*
  exit /b %ERRORLEVEL%
)

rem Check cached binary
if exist "%BINARY%" (
  "%BINARY%" %*
  exit /b %ERRORLEVEL%
)

echo pkdx binary not found. Build locally: >&2
echo   cd pkdx ^&^& moon build --target native >&2
exit /b 1
