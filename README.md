# winmux

> [!IMPORTANT]
> **⚠️ DEPRECATED — superseded by [gpty](https://github.com/samdotson61/gpty).**
> winmux and [win-pty](https://github.com/samdotson61/win-pty) were merged into
> the single cross-platform [gpty](https://github.com/samdotson61/gpty) module:
> **`gmux` replaces `wmux`** (same commands, same tmux passthrough) and `gpty`
> replaces `win-pty`. This repo is kept for history and receives no further
> updates.

Run a **real, native `tmux` on Windows** — no WSL — with **PowerShell 7 panes by
default** and MSYS2 `bash` one keystroke away. Includes the config and launcher
to let [win-pty](https://github.com/samdotson61/win-pty) (the Windows agent-pty
fork, or any MCP agent) drive it.

There is no native Windows build of tmux — it's a Unix program. The trick is the
**MSYS2** distribution, which ships a genuine native `tmux.exe` built on the
cygwin runtime. This repo gets that running and wires PowerShell into it.

## Quick start

```powershell
# one-time: installs MSYS2 + native tmux, ensures Go and compiles the single
# static wmux.exe, installs the tmux config, and puts `wmux` on your PATH.
# (Double-click install.cmd, or:)
./install.ps1

# then open a NEW terminal:
wmux new -t test     # native tmux session with a PowerShell-7 pane, attached
```

(`install.ps1` is idempotent — safe to re-run.) To drive tmux from an agent,
pair this with [win-pty](https://github.com/samdotson61/win-pty).

A tmux pane now runs **PowerShell 7**. Inside tmux (default prefix `Ctrl-b`):

| Keys | Action |
|---|---|
| `prefix` `B` | new window running MSYS2 bash |
| `prefix` `b` | split current pane into bash |
| `prefix` `\|` / `prefix` `-` | split into bash (vertical / horizontal) |
| `prefix` `R` | reload `~/.tmux.conf` |

## The `wmux` CLI

`wmux` is a single, fast Go binary (`wmux.exe`, built by `install.ps1` — no
PowerShell cold start) that wraps the MSYS2 tmux with the environment it needs
(a UTF-8 locale + `tmux -u` for correct glyphs, tmux on PATH) so you don't have
to type the full `C:\msys64\usr\bin\tmux.exe` path or remember the cygwin quirks.

Interactive `wmux new` / `wmux attach` attach **natively** in PowerShell /
Windows Terminal via Cygwin's pseudo-console — no `winpty`, no separate `mintty`
window, just tmux in your current terminal like it works on Linux. (The
`MSYS=noglob` flag — which disables that pseudo-console and would cause
`open terminal failed: not a terminal` — is applied only to the non-interactive
commands that pass tmux format strings, never to attach.)

`install.ps1` adds this folder to your user PATH automatically, so after running it
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
(spawn/send/snapshot/wait/list/kill) while you watch or take over. Install it
(`win-pty/install.ps1`) and register its self-locating launcher in
`~/.claude.json` — win-pty's installer prints the exact snippet with the right
path:

```json
"win-pty": {
  "type": "stdio",
  "command": "C:\\path\\to\\win-pty\\win-pty.exe",
  "args": ["mcp"]
}
```

Attach to any agent session from your own PowerShell window while it runs:

```powershell
C:\msys64\usr\bin\tmux.exe attach -t agent-pty-<name>
```

### …or let an agent drive sessions with the `win-pty` CLI from inside a pane

An agent running *inside* a pwsh pane can spawn and steer sibling sessions
directly:

```powershell
win-pty spawn build --cmd "bash -l"
win-pty send build "make<Enter>"
win-pty wait-for build "Done"
win-pty list
```

This works with no per-pane setup because the config runs
[`pane-init.ps1`](pane-init.ps1) in every pwsh pane. The cygwin/tmux environment
round-trip mangles a few Windows variables — `PATHEXT` collapses to a single
bogus token (so PowerShell stops resolving bare command names), `USERNAME` is
emptied, and PATH entries get dropped — which is what makes a bare `win-pty`
fail with *"command not found"* or *"system cannot find the path"*.
`pane-init.ps1` repairs all three: it restores PATHEXT/USERNAME and re-asserts
the persistent (Machine + User) PATH, where `install.ps1` (winmux) and
`win-pty/install.ps1` put their folders — so both `win-pty` and `wmux` resolve
by name. (win-pty is a single Go exe installed on PATH by its own install.ps1.)

## Files

- [`install.ps1`](install.ps1) / [`install.cmd`](install.cmd) — one-click install: MSYS2 + tmux + winpty, ensure Go and build `wmux.exe`, install `tmux.conf`, add this folder to PATH.
- [`go/`](go/) — the `wmux` CLI source (Go); `install.ps1` compiles it to the single static `wmux.exe`.
- [`tmux.conf`](tmux.conf) — PowerShell-7-default config (runs `pane-init.ps1` per pane); installed to `~/.tmux.conf`.
- [`pane-init.ps1`](pane-init.ps1) — per-pane bootstrap: repairs PATHEXT/USERNAME, re-asserts PATH.

The `win-pty` CLI/MCP lives in the companion
[win-pty](https://github.com/samdotson61/win-pty) repo (also a single Go exe,
installed by its own `install.ps1`).

## Notes

- `tmux.conf`'s `default-command` launches pwsh 7 and runs `pane-init.ps1`; for a
  bash-default tmux, point it at `bash -l` instead.
- The MSYS2 `tmux.exe` is a cygwin-runtime program; native Windows console apps
  (like pwsh) run fine in panes, and `winpty` is installed for the rare full-screen
  app that needs it.

## Credits

tmux is by Nicholas Marriott and contributors. MSYS2 provides the native build.
agent-pty is by [AakeshF](https://github.com/AakeshF/agent-pty). This setup
(config, launcher, install script) is by Sam Dotson — MIT licensed.
