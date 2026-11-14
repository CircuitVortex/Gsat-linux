@echo off
rem One-shot: finishes the WSL1 import after the reboot. RunOnce removes this.
set LOG=%TEMP%\opencode\wsl1-finish.log
echo ==== %DATE% %TIME% ==== > "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl1-setup.ps1" >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
