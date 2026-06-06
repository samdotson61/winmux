#requires -version 5
<#
.SYNOPSIS
  wmux - a thin, friendly CLI over the native MSYS2 tmux on Windows.
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
# Prepend the MSYS2 tmux dir and this PowerShell's own install dir ($PSHOME) so
# tmux resolves and its `pwsh` default-command works regardless of whether pwsh
# was installed to Program Files or as a Store app. The inherited PATH is kept.
$env:MSYS = 'noglob'
$tmuxDir = Split-Path $tmux
$env:PATH = "$tmuxDir;$PSHOME;$env:PATH"

function Get-Opt([string[]]$a, [string[]]$names) {
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($names -contains $a[$i] -and ($i + 1) -lt $a.Count) { return $a[$i + 1] }
    }
    return $null
}

# Console-attached call: tmux talks straight to this terminal. Use for output
# (ls) and interactive commands (attach, new-without-d).
function Tmux([string[]]$tmuxArgs) {
    & $tmux @tmuxArgs
    return $LASTEXITCODE
}

# Detached call with every std stream pointed at the NUL device (the analog of
# a POSIX /dev/null on all three fds). No inheritable pipe, so the forked pane
# can't stall us -- a PowerShell-piped child stdout would be held open by a
# long-lived pwsh pane and hang forever -- and tmux gets a clean (non-tty)
# stdin so `new-session -d` doesn't error with "open terminal failed".
function TmuxDetached([string]$argLine) {
    $p = Start-Process -FilePath $tmux -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
        -RedirectStandardInput 'NUL' -RedirectStandardOutput 'NUL' -RedirectStandardError 'NUL'
    return $p.ExitCode
}

$code = 0
switch -Regex ($Command) {
    '^(new|create)$' {
        $name = Get-Opt $Rest @('-t', '-s', '--target', '--name')
        if (-not $name) { Write-Error 'usage: wmux new -t <name> [-c <cmd>] [-d]'; exit 2 }
        $cmd = Get-Opt $Rest @('-c', '--cmd')
        if ($Rest -contains '-d') {
            # detached -> NUL on all streams, no inheritable pipe
            $line = "new-session -d -s `"$name`""
            if ($cmd) { $line += " `"$cmd`"" }
            $code = TmuxDetached $line
            if ($code -eq 0) { Write-Host "created session '$name' (detached). attach: wmux attach -t $name" }
        }
        else {
            # foreground -> create and attach to this terminal
            $a = @('new-session', '-s', $name)
            if ($cmd) { $a += $cmd }
            $code = Tmux $a
        }
    }
    '^(ls|list)$' { $code = Tmux @('list-sessions') }
    '^attach$' {
        $name = Get-Opt $Rest @('-t', '--target')
        $code = if ($name) { Tmux @('attach', '-t', $name) } else { Tmux @('attach') }
    }
    '^kill$' {
        $name = Get-Opt $Rest @('-t', '--target')
        if (-not $name) { Write-Error 'usage: wmux kill -t <name>'; exit 2 }
        $code = Tmux @('kill-session', '-t', $name)
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
        $code = Tmux (@($Command) + $Rest)
    }
}

exit $code
