@echo off
setlocal enabledelayedexpansion
title GeneticBugs Live Simulator
cd /d "%~dp0"
echo ===================================================
echo           Launching GeneticBugs Live Simulator
echo ===================================================

set "GODOT_CMD="

:: 1. Check user-defined environment variables
if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT_CMD=%GODOT_BIN%"
if not defined GODOT_CMD if defined GODOT_EXE if exist "%GODOT_EXE%" set "GODOT_CMD=%GODOT_EXE%"

:: 2. Check system PATH via 'where'
if not defined GODOT_CMD (
    for /f "delims=" %%I in ('where godot 2^>nul') do (
        if exist "%%I" set "GODOT_CMD=%%I"
    )
)

if not defined GODOT_CMD (
    for /f "delims=" %%I in ('where godot4 2^>nul') do (
        if exist "%%I" set "GODOT_CMD=%%I"
    )
)

:: 3. Check known local installation directories
if not defined GODOT_CMD (
    if exist "C:\Users\Admin\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe" (
        set "GODOT_CMD=C:\Users\Admin\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe"
    )
)

if not defined GODOT_CMD (
    if exist "C:\Users\Admin\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" (
        set "GODOT_CMD=C:\Users\Admin\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
    )
)

:: 4. Search user's Downloads directory for any Godot 4 binary
if not defined GODOT_CMD (
    for /r "%USERPROFILE%\Downloads" %%F in (Godot_v4*.exe) do (
        if not defined GODOT_CMD if exist "%%F" set "GODOT_CMD=%%F"
    )
)

:: 5. Validate that an executable was found
if not defined GODOT_CMD (
    echo.
    echo [ERROR] Godot 4 executable was not found.
    echo Please ensure Godot 4 is installed and added to your PATH,
    echo or set the GODOT_BIN environment variable to its location.
    echo.
    pause
    exit /b 1
)

echo Found Godot: "!GODOT_CMD!"
echo Launching live arena...
echo.

"!GODOT_CMD!" --path "%~dp0godot"
if !ERRORLEVEL! neq 0 (
    echo.
    echo [WARNING] Godot exited with error code !ERRORLEVEL!.
    pause
)

endlocal