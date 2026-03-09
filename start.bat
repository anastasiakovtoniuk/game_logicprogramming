@echo off
echo ================================================
echo  Reversi - Prolog AI Game Server
echo ================================================
echo.

REM Kill any old server instances first
echo Stopping old SWI-Prolog instances...
powershell -Command "Get-Process swipl -ErrorAction SilentlyContinue | Stop-Process -Force"
timeout /t 1 /nobreak >nul

REM Try swipl from PATH first
where swipl >nul 2>&1
if %errorlevel%==0 (
    echo Starting server at http://localhost:8080/
    echo Press Ctrl+C to stop.
    echo.
    swipl reversi.pl
    goto :end
)

REM Try default install location
set SWIPL="C:\Program Files\swipl\bin\swipl.exe"
if exist %SWIPL% (
    echo Starting server at http://localhost:8080/
    echo Press Ctrl+C to stop.
    echo.
    %SWIPL% reversi.pl
    goto :end
)

echo ERROR: swipl not found.
echo Install SWI-Prolog from https://www.swi-prolog.org/
pause

:end
