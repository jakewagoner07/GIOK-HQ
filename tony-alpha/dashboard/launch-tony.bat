@echo off
REM ==============================================================
REM  Tony Alpha - desktop launcher
REM  Double-click this file to open the Tony Alpha dashboard.
REM  (Later this .bat becomes the target of a desktop-icon shortcut.)
REM ==============================================================
setlocal
set "HERE=%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%dashboard.ps1"
if errorlevel 1 (
  echo.
  echo Tony Alpha exited with an error. Press any key to close.
  pause >nul
)
endlocal
