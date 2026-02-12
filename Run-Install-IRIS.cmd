@echo off
REM Launcher for Install-IRIS.ps1 when execution policy blocks scripts.
REM Run this from the same folder as Install-IRIS.ps1 (or pass full path to the .ps1).
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Install-IRIS.ps1" %*
