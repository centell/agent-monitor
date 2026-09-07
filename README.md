# agent-monitor

**Which of your agent sessions is waiting for you?**

A macOS menu bar app for people who keep several Claude Code sessions open at once. The hard
question is not *what are they doing* — it is *which one has finished and is waiting for me*.

한국어 문서는 [README.ko.md](README.ko.md) 에 있습니다.

---

## What it shows

The menu bar shows `2/5` — two waiting, five alive. That is all. It never grows with the session
count and it never truncates the list.

Click it and every session is on one screen, no folding, the ones needing you on top:

```
◆  payments-api     Approval   Bash    2m      █▎   RAM  0.6G  CPU   0%
○  docs-site        Idle       —      20m      ▊    RAM  0.4G  CPU   0%
──────────────────────────────────────────────────────────────────────
●  web-client       Working    Read    4s      █▌   RAM  0.8G  CPU  12%
◐  data-pipeline    Shell      Bash   31s      █▍   RAM  0.7G  CPU   3%
──────────────────────────────────────────────────────────────────────
Memory 15.6/25.8GB · Swap 12.3GB · Agents 3.7GB
```

| Marker | Status | Needs you |
|---|---|---|
| `◆` | `waiting` — a permission prompt is open | **yes** |
| `○` | `idle` — the turn ended, it wants input | **yes** |
| `●` | `busy` — generating | no |
| `◐` | `shell` — a shell command is running | no |

Status comes from the file Claude Code writes for itself, not from guessing at file timings — so a
pending approval and a long shell command are told apart instead of both looking like silence.

Click a row and the terminal window running that session comes to the front.

## Install

### Download a build

[Releases](https://github.com/centell/agent-monitor/releases) carries a prebuilt universal app.

> **It is not signed or notarised.** Signing for distribution needs a paid Apple Developer
> account, which this project does not have. macOS will refuse to open it the first time.

1. Unzip, and put `AgentMonitor.app` wherever you keep apps
2. **Right-click the app → Open**, then confirm in the dialog
3. If macOS still refuses: System Settings → Privacy & Security → scroll down → **Open Anyway**

Once is enough; later launches are normal. Or build it yourself instead — two commands, about
fifteen seconds.

### Build from source

Requires the Swift compiler (`xcode-select --install`). No other dependencies.

```sh
git clone https://github.com/centell/agent-monitor.git
cd agent-monitor
./build.sh
```

`build.sh` compiles and installs to `~/Applications/AgentMonitor.app`, then launches it. Building
again replaces the app and relaunches it if it was running. Pass `--no-run` to skip the relaunch.

The first time you click a session row, macOS asks for permission to control Terminal. That
permission is what moves the window; without it the jump does nothing.

## Using it

**Menu bar** — the count. Click for the list. `⌘,` opens settings.

**Settings** has two tabs:

- **Display** — language, line layout, which columns to show, metric detail, refresh interval. A
  live preview renders real sessions through the same code the menu uses, so what you see is what
  you get.
- **Memory** — system used/swap/compressed, the agent total, and the largest consumers outside
  every session tree. Per-session memory is summed across the whole process tree, not the `claude`
  process alone, which is usually several times larger.

**Command line** — the same data without the GUI:

```sh
agent-monitor --list      # human-readable table
agent-monitor --json      # machine-readable
agent-monitor --memory    # what is using RAM on this machine
agent-monitor --roots     # which account roots are scanned
```

The interface is available in English and Korean, following the system language by default.

## Limitations

- **Session status comes from an undocumented internal file.** Observed on Claude Code 2.1.263. If
  the format changes this breaks; there is a fallback that reads the transcript instead, and rows
  using it are marked as estimates rather than failing silently.
- **Terminal.app only** for the jump-to-terminal feature. iTerm2, Ghostty, WezTerm and kitty each
  need their own automation path. Inside tmux it reaches the window but not the pane.
- **Servers a session spawned can escape its total.** A dev server or container that detaches from
  the process tree is not counted in that session. The memory tab lists them separately, and says
  "multiple sessions (n)" rather than guessing when several sessions share a project.
- **Unsigned.** Releases are not signed or notarised, so macOS blocks the first launch.
- **macOS only**, universal (Apple Silicon and Intel), built against the macOS 13 SDK but only run
  on macOS 26. It knows about Claude Code and nothing else so far.

## License

MIT — see [LICENSE](LICENSE).
