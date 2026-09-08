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

Hover a row that needs you and it says **why**. A session waiting on approval shows the call it
is waiting on (`Bash: pnpm build --filter web`); an idle one shows the last thing it said to you
(`Shall I commit, or leave it for the review?`). A busy row says nothing — there is nothing for
you to answer yet.

It lives on hover rather than in the row on purpose. In the row it charged width to every line,
including the working ones that had nothing to say, and the reason itself still arrived cut in
half — usually losing the end of the question, which is the part that asks. On hover it costs no
width and is never truncated. The text comes out of the transcript the app was already reading,
so it costs no extra work, and when it is not there nothing is shown rather than a guess. Turn it
off in Display if you would rather not have commands on screen; `--json` carries it as `reason`.

Click a row and the terminal window running that session comes to the front.

Right-click a row to **pin** it. A pinned session rises above the others while it waits for you,
and carries a tinted background. While it is working it keeps its place — there is nothing for
you to do there yet. A pin lives with its session; restart the session and you pin it again.

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

**Settings** has three tabs:

- **Display** — language, line layout, which columns to show, whether hovering a row says why it
  is waiting, which of the three metrics to show
  (RAM bar, RAM GB, CPU % — each on its own switch), refresh interval. A live preview renders real
  sessions through the same code the menu uses, so what you see is what you get.
- **Memory** — system used/swap/compressed, the agent total, and the largest consumers outside
  every session tree. Per-session memory is summed across the whole process tree, not the `claude`
  process alone, which is usually several times larger.
- **Statistics** — whether recording is alive (how much piled up today, when the last row landed),
  then the same numbers `--stats` prints: the last 7 days, by hour and by weekday, with a bar on
  the share of time two or more sessions were waiting.

**Command line** — the same data without the GUI:

```sh
agent-monitor --list      # human-readable table
agent-monitor --json      # machine-readable
agent-monitor --memory    # what is using RAM on this machine
agent-monitor --roots     # which account roots are scanned
agent-monitor --stats     # how you have actually been using it (7 days; --stats 30 for a month)
```

The interface is available in English and Korean, following the system language by default.

## How many sessions can you actually feed?

Running more sessions only helps while you can keep up with them. A session produces nothing while
it waits for you, and you are one person — so once a queue has formed, another session mostly adds
RAM. The app already measures the queue every couple of seconds, so it records it.

```
$ agent-monitor --stats
Last 7 days — 4 days recorded · 21.6 hours at the keyboard

  Sessions          4.2 avg · 7 peak
  Actually running  1.6 avg
  Queue length      none 12% · one 47% · two+ 41%
  Waiting time      median 3m 12s · longest 41m · total 3h 42m  (44×)
  Agent RAM         3.1GB avg · 5.4GB peak · swap 12.3GB avg
```

Read it as a queue: **two or more** waiting is time you were behind, **none** waiting is time you
had spare. The numbers above say the queue is standing three times as often as the hands are free.

The same numbers are broken down by hour and by weekday, which is where a different question shows
up. Being at the keyboard is not the same as working on the sessions — a call, a chat window, an
evening of something else all count as present, and the queue grows through them. An hour where
**little is running but the queue is long** is that: not too many sessions, just attention
elsewhere.

```
시간대별
  시간     앞에 계신     세션  돌던 수  줄 둘 이상
  10시          1.1h      5.0      1.9         58%
  22시          0.3h      6.0      0.4         96%
```

Buckets holding less than five minutes are left out, and the line below the table says how many —
a two-minute bucket reading 100% is chance, not habit.

Everything is counted only while you are at the keyboard, found from the time of your last input.
Without that split, a night's sleep makes five idle sessions look like a five-deep queue, and every
day would read the same. Recording keeps counts, durations and memory — never conversation content
— and can be switched off in Display. Files live in
`~/Library/Application Support/AgentMonitor/stats/` as CSV, one file per day, kept for 30 days.

There is deliberately no "you should run N sessions" line yet. The threshold that would justify one
has to come from recorded days, not from a guess made before any day was recorded.

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
