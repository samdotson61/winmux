@echo off
rem One-click installer for winmux. Double-click this file, or run it from a
rem terminal. It installs MSYS2 + tmux, checks for Go (installs via winget if
rem missing), builds the single wmux.exe, installs the tmux config, and puts
rem this folder on your PATH.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
