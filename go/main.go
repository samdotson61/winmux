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

// wmuxEnv: UTF-8 locale + MSYS=noglob, and prepend the tmux dir and this exe's
// own dir to PATH (so panes can resolve co-located launchers like win-pty).
func wmuxEnv() []string {
	env := os.Environ()
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
	set("MSYS", "noglob")
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

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode()
	}
	return 1
}

// console: tmux talks to the real terminal (attach / interactive / output).
func console(args ...string) int {
	c := exec.Command(tmuxBin(), append([]string{"-u"}, args...)...)
	c.Env = wmuxEnv()
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
			code = console(a...)
		}
	case "ls", "list":
		code = console("list-sessions")
	case "attach":
		if name := opt(rest, "-t", "--target"); name != "" {
			code = console("attach", "-t", name)
		} else {
			code = console("attach")
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
