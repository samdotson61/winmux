# winmux

Run a **real, native `tmux` on Windows** — no WSL — with **PowerShell 7 panes by
default** and MSYS2 `bash` one keystroke away. Includes the config and launcher
to let [win-pty](https://github.com/samdotson61/win-pty) (the Windows agent-pty
fork, or any MCP agent) drive it.

There is no native Windows build of tmux — it's a Unix program. The trick is the
**MSYS2** distribution, which ships a genuine native `tmux.exe` built on the
cygwin runtime. This repo gets that running and wires PowerShell into it.

## Quick start

```powershell
# 1. Install MSYS2 + native tmux (one-time)
./setup.ps1

# 2. Drop the tmux config into your MSYS2 home
Copy-Item tmux.conf "$env:USERPROFILE\..\..\msys64\home\$env:USERNAME\.tmux.conf"
#   (or simply copy tmux.conf to C:\msys64\home\<you>\.tmux.conf)

# 3. Launch tmux from any PowerShell window
C:\msys64\usr\bin\tmux.exe
```

A tmux pane now runs **PowerShell 7**. Inside tmux (default prefix `Ctrl-b`):

| Keys | Action |
|---|---|
| `prefix` `B` | new window running MSYS2 bash |
| `prefix` `b` | split current pane into bash |
| `prefix` `\|` / `prefix` `-` | split into bash (vertical / horizontal) |
| `prefix` `R` | reload `~/.tmux.conf` |

## The `wmux` CLI

`wmux` is a thin, friendly wrapper around the MSYS2 tmux that sets up the
environment for you (`MSYS=noglob`, tmux + pwsh on PATH) so you don't have to
type the full `C:\msys64\usr\bin\tmux.exe` path or remember the cygwin quirks.

`setup.ps1` adds this folder to your user PATH automatically, so after running it
(and opening a **new** terminal) `wmux` just works. To add it by hand instead:

```powershell
# one-time, current user
$dir = "C:\Claude\winmux"   # wherever this repo lives
[Environment]::SetEnvironmentVariable(
    "PATH", "$dir;" + [Environment]::GetEnvironmentVariable("PATH","User"), "User")
# then reopen your terminal
```

Once it's on PATH:

```powershell
wmux new -t test                  # new PowerShell-7 session "test", and attach
wmux new -t build -c "bash -l" -d # create a detached bash session
wmux ls                           # list sessions
wmux attach -t test               # attach (detach again with Ctrl-b d)
wmux kill -t test                 # kill a session
wmux split-window -h              # anything unrecognized is passed to tmux
```

| Command | Does |
|---|---|
| `wmux new -t <name> [-c <cmd>] [-d]` | create a session (attaches unless `-d`); default pane is pwsh 7 |
| `wmux ls` | list sessions |
| `wmux attach -t <name>` | attach to a session |
| `wmux kill -t <name>` | kill a session |
| `wmux <tmux args…>` | passed straight through to tmux |

`wmux` honours `WMUX_TMUX` (path to `tmux.exe`) and `MSYS2_ROOT` (default
`C:\msys64`) if your install lives elsewhere.

## Let an agent control it

[win-pty](https://github.com/samdotson61/win-pty) (the Windows fork of agent-pty)
is an MCP server that gives an LLM agent a persistent terminal it can drive
(spawn/send/snapshot/wait/list/kill) while you watch or take over. Once it's
installed, register the server with the included launcher. In `~/.claude.json`:

```json
"agent-pty": {
  "type": "stdio",
  "command": "cmd.exe",
  "args": ["/c", "C:\\Claude\\winmux\\agent-pty-mcp.cmd"]
}
```

Edit [`agent-pty-mcp.cmd`](agent-pty-mcp.cmd) so its Python path points at your
win-pty checkout. The wrapper prepends the MSYS2 `tmux` dir and PowerShell 7
to `PATH` (keeping the full Windows `PATH`) and sets `MSYS=noglob`.

Attach to any agent session from your own PowerShell window while it runs:

```powershell
C:\msys64\usr\bin\tmux.exe attach -t agent-pty-<name>
```

## Files

- [`setup.ps1`](setup.ps1) — installs MSYS2 (via winget) and `tmux` + `winpty` (via pacman).
- [`tmux.conf`](tmux.conf) — PowerShell-7-default config; copy to `~/.tmux.conf` in MSYS2 home.
- [`wmux.ps1`](wmux.ps1) / [`wmux.cmd`](wmux.cmd) — the `wmux` CLI (put this folder on PATH).
- [`agent-pty-mcp.cmd`](agent-pty-mcp.cmd) — MCP launcher that puts tmux + pwsh on PATH.

## Notes

- `tmux.conf`'s `default-command` is `pwsh -NoLogo`; remove that line for a bash-default tmux.
- The MSYS2 `tmux.exe` is a cygwin-runtime program; native Windows console apps
  (like pwsh) run fine in panes, and `winpty` is installed for the rare full-screen
  app that needs it.

## Credits

tmux is by Nicholas Marriott and contributors. MSYS2 provides the native build.
agent-pty is by [AakeshF](https://github.com/AakeshF/agent-pty). This setup
(config, launcher, install script) is by Sam Dotson — MIT licensed.
