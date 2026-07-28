@echo off
rem Doppio click per generare dist\WinGetUpdateTool.exe.
rem -ExecutionPolicy Bypass: evita di dover sbloccare i .ps1 sulla macchina.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\build.ps1"
echo.
pause
