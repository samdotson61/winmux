#requires -version 5
<#
.SYNOPSIS
  wmux — a thin, friendly CLI over the native MSYS2 tmux on Windows.
.DESCRIPTION
  Wraps C:\msys64\usr\bin\tmux.exe with the environment the cygwin runtime needs
  (MSYS=noglob, tmux + PowerShell 7 on PATH) and a few convenient subcommands.
  Anything it doesn't recognize is passed straight through to tmux, so the full
  tmux command set is still available (e.g. `wmux split-window -h`).

  Session names use -t everywhere for consistency (tmux's own `new-session`
  uses -s; wmux accepts either and translates).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'

# --- locate the native MSYS2 tmux -------------------------------------------
$msysRoot = if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { 'C:\msys64' }
$tmux = if ($env:WMUX_TMUX) { $env:WMUX_TMUX } else { Join-Path $msysRoot 'usr\bin\tmux.exe' }
if (-not (Test-Path $tmux)) {
    Write-Error "tmux not found at '$tmux'. Run winmux's setup.ps1, or set `$env:WMUX_TMUX."
    exit 1
}

# --- environment the cygwin tmux needs --------------------------------------
$env:MSYS = 'noglob'
$tmuxDir = Split-Path $tmux
$pwshDir = 'C:\Program Files\PowerShell\7'
$env:PATH = "$tmuxDir;$pwshDir;$env:PATH"

function Get-Opt([string[]]$a, [string[]]$names) {
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($names -contains $a[$i] -and ($i + 1) -lt $a.Count) { return $a[$i + 1] }
    }
    return $null
}

function Invoke-Tmux([string[]]$tmuxArgs) {
    & $tmux @tmuxArgs
    return $LASTEXITCODE
}

$code = 0
switch -Regex ($Command) {
    '^(new|create)$' {
        $name = Get-Opt $Rest @('-t', '-s', '--target', '--name')
        if (-not $name) { Write-Error 'usage: wmux new -t <name> [-c <cmd>] [-d]'; exit 2 }
        $cmd = Get-Opt $Rest @('-c', '--cmd')
        $a = @('new-session')
        if ($Rest -contains '-d') { $a += '-d' }     # detached; otherwise attaches
        $a += @('-s', $name)
        if ($cmd) { $a += $cmd }
        $code = Invoke-Tmux $a
    }
    '^(ls|list)$' { $code = Invoke-Tmux @('list-sessions') }
    '^attach$' {
        $name = Get-Opt $Rest @('-t', '--target')
        $code = if ($name) { Invoke-Tmux @('attach', '-t', $name) } else { Invoke-Tmux @('attach') }
    }
    '^kill$' {
        $name = Get-Opt $Rest @('-t', '--target')
        if (-not $name) { Write-Error 'usage: wmux kill -t <name>'; exit 2 }
        $code = Invoke-Tmux @('kill-session', '-t', $name)
    }
    '^(|-h|--help|help)$' {
        @'
wmux - native tmux on Windows (MSYS2), PowerShell-7 panes by default.

  wmux new -t <name> [-c <cmd>] [-d]   create a session (attaches unless -d)
  wmux ls                              list sessions
  wmux attach -t <name>                attach to a session
  wmux kill -t <name>                  kill a session
  wmux <tmux args...>                  anything else is passed to tmux

Examples:
  wmux new -t test                     # new pwsh session named "test", attach
  wmux new -t build -c "bash -l" -d    # detached bash session
  wmux ls
  wmux attach -t test
  wmux kill -t test

Env: WMUX_TMUX (tmux.exe path), MSYS2_ROOT (default C:\msys64).
'@ | Write-Host
    }
    default {
        # Unknown command -> pass through verbatim to tmux.
        $all = @($Command) + $Rest
        $code = Invoke-Tmux $all
    }
}

exit $code
