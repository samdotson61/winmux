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

# 2b. Ensure Go, then build the single static wmux.exe (tool + deps, no pwsh).
function Resolve-Go {
    $c = Get-Command go -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = Join-Path $env:ProgramFiles 'Go\bin\go.exe'
    if (Test-Path $p) { return $p }
    return $null
}
$go = Resolve-Go
if (-not $go) {
    Info 'Go not found - installing via winget (GoLang.Go)...'
    winget install --id GoLang.Go --accept-source-agreements --accept-package-agreements --disable-interactivity
    $go = Resolve-Go
    if (-not $go) { throw 'Go install did not produce go.exe. Install Go from https://go.dev/dl and re-run.' }
}
Info "Building wmux.exe with $(& $go version)"
$wmuxExe = Join-Path $PSScriptRoot 'wmux.exe'
Push-Location (Join-Path $PSScriptRoot 'go')
try {
    & $go build -o $wmuxExe .
    if ($LASTEXITCODE -ne 0) { throw 'go build (wmux) failed.' }
} finally { Pop-Location }
if (-not (Test-Path $wmuxExe)) { throw 'wmux.exe was not produced.' }
Info "Built: $wmuxExe ($([math]::Round((Get-Item $wmuxExe).Length/1MB,1)) MB, no runtime deps)"

# 3. tmux.conf with @@WINMUX@@ resolved to this folder. A cygwin tmux's HOME
#    differs by launch context (pwsh -> Windows profile; bash login -> /home),
#    so write to every plausible location so tmux always finds it.
$src       = Join-Path $PSScriptRoot 'tmux.conf'
$winmuxFwd = $PSScriptRoot -replace '\\', '/'                  # tmux wants /-paths
$content   = (Get-Content $src -Raw).Replace('@@WINMUX@@', $winmuxFwd)
$msysHome  = & $bash -lc 'echo $HOME'
$dests = @(
    (& $bash -lc "cygpath -w `"$msysHome/.tmux.conf`""),
    (Join-Path $Msys2Root "home\$env:USERNAME\.tmux.conf"),
    (Join-Path $env:USERPROFILE '.tmux.conf')
) | Where-Object { $_ } | Select-Object -Unique
foreach ($dest in $dests) {
    $dir = Split-Path $dest
    if (-not (Test-Path $dir)) { continue }
    if (Test-Path $dest) { Copy-Item $dest "$dest.bak" -Force }
    Info "Installing tmux.conf -> $dest"
    $content | Set-Content $dest -NoNewline -Encoding utf8
}

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
