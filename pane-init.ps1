# pane-init.ps1 — bootstrap run by every wmux/win-pty PowerShell pane.
#
# Two things the cygwin/tmux environment breaks for panes, fixed here (in pwsh,
# after the mangling, so it actually sticks):
#
#  1. PATHEXT. The cygwin env round-trip collapses the Windows ';'-separated
#     PATHEXT down to a single bogus token, so PowerShell stops resolving bare
#     command names (`win-pty`, `wmux`) to their .cmd launchers. Re-assert a
#     sane PATHEXT, but only when it's actually broken — a normal shell keeps
#     its own (possibly richer) value untouched.
#
#  2. PATH. Make this folder (which holds wmux.cmd / win-pty.cmd) resolvable so
#     an agent in a pane can drive sessions with `win-pty ...` and `wmux ...`
#     with no extra setup.

# 0. USERNAME. The cygwin/tmux env strips USERNAME (and USER), but the .cmd
#    launchers reference %USERNAME% to locate the install under the MSYS2 home.
#    Repopulate it from the real Windows account name.
if (-not $env:USERNAME) { $env:USERNAME = [Environment]::UserName }

if ($env:PATHEXT -notlike '*.CMD*') {
    $env:PATHEXT = '.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC'
}

$here = $PSScriptRoot
if ($here -and (($env:PATH -split ';') -notcontains $here)) {
    $env:PATH = "$here;$env:PATH"
}
