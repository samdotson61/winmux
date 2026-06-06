package main

// wmux — a thin, fast, single-binary CLI over the native MSYS2 tmux on Windows.
// Replaces the wmux.ps1 + wmux.cmd pair (no pwsh cold start). Sets the env tmux
// needs (MSYS=noglob, a UTF-8 locale, tmux -u) so glyphs/format strings aren't
// mangled, and hands interactive commands the real console.
//
//   wmux new -t <name> [-c <cmd>] [-d]   create a session (attaches unless -d)
//   wmux ls                              list sessions
//   wmux attach -t <name>                attach to a session
//   wmux kill -t <name>                  kill a session
//   wmux <tmux args...>                  passed straight through to tmux

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func tmuxBin() string {
	if v := os.Getenv("WMUX_TMUX"); v != "" {
		return v
	}
	if p, err := exec.LookPath("tmux"); err == nil {
		return p
	}
	root := os.Getenv("MSYS2_ROOT")
	if root == "" {
		root = `C:\msys64`
	}
	return filepath.Join(root, `usr\bin\tmux.exe`)
}

// buildEnv assembles the env tmux runs with: always a UTF-8 locale (so the
// block-art glyphs Claude draws survive) and tmux + this exe's dir on PATH (so
// panes resolve co-located tools). MSYS=noglob is applied ONLY when noglob=true.
//
// Why noglob is conditional: MSYS=noglob disables Cygwin's pseudo-console
// (pcon), and the interactive tmux CLIENT needs pcon to attach to a native
// Windows console — without it tmux dies with "open terminal failed: not a
// terminal" (raw `tmux new` attaches fine from pwsh; MSYS=noglob is what broke
// it). So attach/new use attachEnv (noglob=false). Only commands that pass tmux
// FORMAT strings as args — which Cygwin would brace-expand, #{x} -> #x — need
// wmuxEnv (noglob=true). Any inherited MSYS is stripped first so we fully
// control it.
func buildEnv(noglob bool) []string {
	env := os.Environ()
	kept := env[:0]
	for _, e := range env {
		if !strings.HasPrefix(e, "MSYS=") {
			kept = append(kept, e)
		}
	}
	env = kept
	set := func(k, v string) {
		pre := k + "="
		for i, e := range env {
			if strings.HasPrefix(e, pre) {
				env[i] = pre + v
				return
			}
		}
		env = append(env, pre+v)
	}
	if noglob {
		set("MSYS", "noglob")
	}
	lang := os.Getenv("LANG")
	if u := strings.ToUpper(lang); !strings.Contains(u, "UTF-8") && !strings.Contains(u, "UTF8") {
		lang = "C.UTF-8"
		set("LANG", lang)
	}
	set("LC_CTYPE", lang)

	tmuxDir := filepath.Dir(tmuxBin())
	exeDir := ""
	if exe, err := os.Executable(); err == nil {
		exeDir = filepath.Dir(exe)
	}
	for i, e := range env {
		if strings.HasPrefix(e, "PATH=") || strings.HasPrefix(e, "Path=") {
			env[i] = "PATH=" + exeDir + ";" + tmuxDir + ";" + strings.SplitN(e, "=", 2)[1]
			return env
		}
	}
	env = append(env, "PATH="+exeDir+";"+tmuxDir)
	return env
}

// wmuxEnv: env WITH MSYS=noglob — format-string-safe, for non-attaching paths.
func wmuxEnv() []string { return buildEnv(true) }

// attachEnv: env WITHOUT MSYS=noglob, so Cygwin's pcon can give tmux a real pty
// on a native Windows console.
func attachEnv() []string { return buildEnv(false) }

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode()
	}
	return 1
}

// console: tmux talks to the real terminal, WITH MSYS=noglob. For output and
// pass-through commands that may carry tmux format strings (ls, kill, etc.).
func console(args ...string) int {
	c := exec.Command(tmuxBin(), append([]string{"-u"}, args...)...)
	c.Env = wmuxEnv()
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	return exitCode(c.Run())
}

// interactive: an ATTACHING tmux (new-and-attach, or `attach`). Like console
// but with attachEnv (no MSYS=noglob) so Cygwin's pcon gives tmux a real pty on
// the native Windows console — the fix for "open terminal failed: not a
// terminal".
func interactive(args ...string) int {
	c := exec.Command(tmuxBin(), append([]string{"-u"}, args...)...)
	c.Env = attachEnv()
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	return exitCode(c.Run())
}

// detached: no console, null std streams (won't block; safe with no tty).
func detached(args ...string) int {
	c := exec.Command(tmuxBin(), append([]string{"-u"}, args...)...)
	c.Env = wmuxEnv()
	return exitCode(c.Run())
}

// opt finds the value for any of the given flag names.
func opt(args []string, names ...string) string {
	for i := 0; i < len(args); i++ {
		for _, n := range names {
			if args[i] == n && i+1 < len(args) {
				return args[i+1]
			}
		}
	}
	return ""
}
func hasFlag(args []string, f string) bool {
	for _, a := range args {
		if a == f {
			return true
		}
	}
	return false
}

const usage = `wmux - native tmux on Windows (MSYS2), PowerShell-7 panes by default.
  wmux new -t <name> [-c <cmd>] [-d]   create a session (attaches unless -d)
  wmux ls                              list sessions
  wmux attach -t <name>                attach to a session
  wmux kill -t <name>                  kill a session
  wmux <tmux args...>                  anything else is passed to tmux
Env: WMUX_TMUX (tmux.exe path), MSYS2_ROOT (default C:\msys64).`

func main() {
	if len(os.Args) < 2 {
		fmt.Println(usage)
		os.Exit(0)
	}
	cmd := os.Args[1]
	rest := os.Args[2:]
	var code int
	switch cmd {
	case "new", "create":
		name := opt(rest, "-t", "-s", "--target", "--name")
		if name == "" {
			fmt.Fprintln(os.Stderr, "usage: wmux new -t <name> [-c <cmd>] [-d]")
			os.Exit(2)
		}
		run := opt(rest, "-c", "--cmd")
		if hasFlag(rest, "-d") {
			a := []string{"new-session", "-d", "-s", name}
			if run != "" {
				a = append(a, run)
			}
			code = detached(a...)
			if code == 0 {
				fmt.Printf("created session '%s' (detached). attach: wmux attach -t %s\n", name, name)
			}
		} else {
			a := []string{"new-session", "-s", name}
			if run != "" {
				a = append(a, run)
			}
			code = interactive(a...)
		}
	case "ls", "list":
		code = console("list-sessions")
	case "attach":
		if name := opt(rest, "-t", "--target"); name != "" {
			code = interactive("attach", "-t", name)
		} else {
			code = interactive("attach")
		}
	case "kill":
		name := opt(rest, "-t", "--target")
		if name == "" {
			fmt.Fprintln(os.Stderr, "usage: wmux kill -t <name>")
			os.Exit(2)
		}
		code = console("kill-session", "-t", name)
	case "-h", "--help", "help", "":
		fmt.Println(usage)
	default:
		code = console(append([]string{cmd}, rest...)...)
	}
	os.Exit(code)
}
