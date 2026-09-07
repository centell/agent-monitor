# agent-monitor

**Which of your agent sessions is waiting for you?**

A macOS menu bar app for people who keep several Claude Code sessions open at once. The hard
question is not *what are they doing* — it is *which one has finished and is waiting for me*.
This answers that with one number in the menu bar and a flat list behind it.

> **English and Korean.** The interface follows your Mac's language by default and can be set
> explicitly in Settings. Source comments are in Korean — see [Contributing](#contributing).

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

Click a row and the terminal window running that session comes to the front.

## Why it exists

The question worth answering is not *what is this session doing* — it is *has it stopped, and is
it waiting for me*. An answer to that has to be a fact, not an inference.

Guessing state from how recently a transcript file changed cannot separate a long-running shell
command from a prompt waiting for approval; both look like silence. Claude Code writes its own
status to disk, so this reads that instead and derives nothing from it.

## How it measures

**State comes from the registry, not from guesswork.** Claude Code writes
`<account-root>/sessions/<pid>.json` with a `status` field. This reads it and shows the value
without deriving anything from it. An unrecognised status is shown verbatim rather than collapsed.

- **All account roots** are scanned — `~/.claude`, `~/.claude-accounts/*/` and `CLAUDE_CONFIG_DIR`.
  Registries are per-root even when `projects/` is shared.
- **Liveness** is confirmed by matching the kernel's process start time against the registry's
  `startedAt`, not by executable name or path, which differ between install methods.
- **Memory is the whole process tree**, not the `claude` process alone. In one measurement a
  session showed 541 MB on its own and 2790 MB across its 26 descendants.
- **CPU** is derived from the difference between two samples; there is no instantaneous reading.
- **Terminal jump** links a session to its window by `tty`.

A full sample costs about 12 ms — roughly 0.6 % of the default two-second cycle.

## Install

Requires the Swift compiler (`xcode-select --install`). No other dependencies.

The bundle declares **macOS 13+**, but it has only been run on macOS 26. If it fails on an
older release, that is untested ground rather than a supported configuration — please open an issue.

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
- **Memory** — system used/swap/compressed, the agent total, and the largest consumers
  outside every session tree. Processes whose working directory sits under a session's folder are
  listed separately as *suspected spawns* and are never folded into the session total.

**Command line** — the same data without the GUI:

```sh
agent-monitor --list      # human-readable table
agent-monitor --json      # machine-readable
agent-monitor --memory    # what is using RAM on this machine
agent-monitor --roots     # which account roots are scanned
```

## Limitations

- **The registry is an undocumented internal file.** Observed on Claude Code 2.1.263. If the format
  changes this breaks; there is a transcript-based fallback, and when it is in use the row is
  marked as an estimate rather than failing silently.
- **Terminal.app only.** iTerm2, Ghostty, WezTerm and kitty each need their own automation path.
  Inside tmux the jump reaches the window but not the pane.
- **Spawned servers can escape the count.** A dev server or container that detaches from the
  session's process tree is not in that session's total. The memory tab surfaces them, but the
  attribution is a guess from the working directory and says so — when several sessions share a
  project it reports "multiple sessions (n)" instead of picking one.
- **Unsigned.** Built locally; there is no notarised release yet.
- **macOS only**, and it only knows about Claude Code so far. `SessionSource` is the seam where
  another CLI would attach.

## Contributing

Issues and pull requests welcome. A few things worth knowing:

- Comments are in Korean and fairly dense — they carry *why*, including decisions that were
  reversed. Please keep that habit rather than stripping it.
- All user-facing text lives in `Sources/Strings.swift`, with the Korean and English wording on
  adjacent lines so a one-sided edit is visible. Adding a language means extending that file.
- Claims in this repo are meant to be measured, not assumed. If you state a number, say how you
  got it; if you could not measure something, say that instead.

## License

MIT — see [LICENSE](LICENSE).
