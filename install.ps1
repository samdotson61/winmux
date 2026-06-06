#requires -version 5
<#
.SYNOPSIS
  Install a native Windows tmux (via MSYS2) with PowerShell-7-default panes.
.DESCRIPTION
  Installs MSYS2 (winget), then tmux + winpty (pacman), and drops tmux.conf into
  the MSYS2 home. No WSL. Idempotent: re-running is safe.
#>
[CmdletBinding()]
param(
    [string]$Msys2Root = 'C:\msys64'
)

$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }

# 1. MSYS2
if (-not (Test-Path "$Msys2Root\usr\bin\bash.exe")) {
    Info 'Installing MSYS2 via winget...'
    winget install --id MSYS2.MSYS2 --accept-source-agreements --accept-package-agreements --disable-interactivity
} else {
    Info "MSYS2 already present at $Msys2Root"
}

$bash = "$Msys2Root\usr\bin\bash.exe"
if (-not (Test-Path $bash)) { throw "MSYS2 bash not found at $bash after install." }

# 2. tmux + winpty
Info 'Installing tmux + winpty via pacman...'
$env:MSYSTEM = 'MSYS'
& $bash -lc 'pacman -S --noconfirm --needed tmux winpty'

# 3. tmux.conf into MSYS2 home, with @@WINMUX@@ resolved to this folder
$home = & $bash -lc 'echo $HOME'
$dest = & $bash -lc "cygpath -w `"$home/.tmux.conf`""
$src  = Join-Path $PSScriptRoot 'tmux.conf'
Info "Installing tmux.conf -> $dest"
if (Test-Path $dest) { Copy-Item $dest "$dest.bak" -Force }   # keep a backup
$winmuxFwd = $PSScriptRoot -replace '\\', '/'                  # tmux wants /-paths
(Get-Content $src -Raw).Replace('@@WINMUX@@', $winmuxFwd) |
    Set-Content $dest -NoNewline -Encoding utf8

# 4. Put this folder (the wmux CLI) on the user PATH
$onPath = ($env:PATH -split ';') -contains $PSScriptRoot
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (($userPath -split ';') -notcontains $PSScriptRoot) {
    Info "Adding $PSScriptRoot to your user PATH (for the 'wmux' command)..."
    $newPath = if ([string]::IsNullOrEmpty($userPath)) { $PSScriptRoot } else { "$PSScriptRoot;$userPath" }
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    # make it usable in THIS session too
    if (-not $onPath) { $env:PATH = "$PSScriptRoot;$env:PATH" }
    $pathChanged = $true
} else {
    Info "wmux already on PATH ($PSScriptRoot)"
}

# 5. Report
$ver = & "$Msys2Root\usr\bin\tmux.exe" -V
Info "Done. $ver installed."
Write-Host ""
Write-Host "The 'wmux' command is installed. Try:" -ForegroundColor Green
Write-Host "    wmux new -t test       # new PowerShell-7 session, attached"
Write-Host "    wmux ls"
Write-Host "Panes default to PowerShell 7; prefix+B for bash."
if ($pathChanged) {
    Write-Host ""
    Write-Host "NOTE: PATH was updated - open a NEW terminal for 'wmux' to resolve." -ForegroundColor Yellow
}
