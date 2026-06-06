@echo off
rem win-pty CLI launcher. Lets an agent (or you) run `win-pty spawn/send/...`
rem from any shell or tmux pane to drive native-Windows tmux sessions.
rem Puts the MSYS2 tmux dir on PATH and sets MSYS=noglob (so tmux format
rem strings and keystroke payloads aren't mangled by the cygwin runtime), then
rem runs the win-pty console script from its venv.
rem Adjust the venv path below if you cloned win-pty somewhere else.
set "PATH=C:\msys64\usr\bin;%PATH%"
set "MSYS=noglob"
"C:\msys64\home\%USERNAME%\agent-pty\.venv-win\Scripts\win-pty.exe" %*
