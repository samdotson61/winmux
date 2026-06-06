@echo off
rem wmux launcher: runs wmux.ps1 from the same folder via PowerShell 7 (falls
rem back to Windows PowerShell if pwsh isn't on PATH). Put this folder on your
rem PATH so you can just type `wmux ...` from any shell.
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0wmux.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wmux.ps1" %*
)
