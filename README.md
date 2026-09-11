# agent-monitor

**Which of your agent sessions is waiting for you?**

A macOS menu bar app for people who keep several agent sessions open at once — Claude Code or
codex, in a terminal or in the desktop app. The hard question is not *what are they doing* — it is
*which one has finished and is waiting for me*.

<p align="center">
  <img src="docs/images/desktop.png" width="358"
       alt="The menu bar reads 1/4. Below it the list is open: one idle session on top, three working ones under a rule.">
</p>

한국어 문서는 [README.ko.md](README.ko.md) 에 있습니다.

---

## What it shows

The menu bar shows `2/5` — two waiting, five alive. That is all. It never grows with the session
count and it never truncates the list.

<img src="docs/images/menubar.png" width="342"
     alt="A menu bar: 1/4 sits at the left, then the input source, wifi, battery and the clock.">

With nobody waiting it reads `0/4` and goes quiet — the count is drawn dimmed while nothing is
yours to answer, and at full strength the moment something is.

<img src="docs/images/menubar-clear.png" width="82"
     alt="The menu bar count reading 0/4 in a muted grey.">


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

The same list on a real machine, in the two-line layout with the source mark on:

<img src="docs/images/menu.png" width="359"
     alt="The open menu: an idle session on top, three working ones below a rule, then the memory summary and the Hide panel, Settings and Quit items.">

| Marker | Status | Needs you |
|---|---|---|
| `◆` | `waiting` — a permission prompt is open | **yes** |
| `○` | `idle` — the turn ended, it wants input | **yes** |
| `●` | `busy` — generating | no |
| `◐` | `shell` — a shell command is running | no |

Status comes from the file Claude Code writes for itself, not from guessing at file timings — so a
pending approval and a long shell command are told apart instead of both looking like silence.

**It watches four places, counted as one list.** The name carries where each row came from.

| Source | Status read from | A click goes to |
|---|---|---|
| Claude Code in a terminal | the registry it writes for itself | its terminal window |
| Claude Code in the desktop app | the end of the transcript — **an estimate** | nowhere; it has no terminal |
| codex in a terminal | the end of the transcript — **an estimate** | its terminal window |
| codex threads in the ChatGPT app | the thread database it writes | the thread, by deep link |

The two that write nothing down are estimated rather than stated, and those rows say so instead of
passing as measured. An app thread has no process of its own — one app runs them all — so it
carries no memory or CPU, and nothing tells us whether a finished one is still open; only threads
finished inside a recent window are listed, which Display sets (10m, 30m, 12h, or hidden).

How the source is written into the name is yours to choose, also in Display: `claude` /
`claude-app`, or `claude-cli` / `claude-app` so all four say what they are, or a single mark that
costs one column — `>` for a terminal, `□` for an app.

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

**A session split across two processes is still one row.** Claude Code can hand a session to
another process while **the terminal window stays with the one it came from**, and the two halves
then break in opposite ways: the one holding the window stops updating its status (three and a
half hours of it, measured), and the one doing the work has no window to go to. The app follows
the handoff recorded in the transcript and joins them, so **the live status and the real terminal
land on the same row**. Their process trees overlap, so the memory is counted once.

## Keeping it open

If you have the screen space, park the list in a corner instead: menu bar → **Show panel**.

It does not replace the menu bar. The `2/5` stays where it is, and on a small screen you simply
leave the panel closed. The only thing that changes is that **the click is gone**.

The rows are the menu's rows, drawn by the same code, so whatever you set in Display comes with
them.

```
 2/5                                                            ▲
 ◆  payments-api     Approval   Bash    2m      █▎   RAM  0.6G
 ○  docs-site        Idle       —      20m      ▊    RAM  0.4G
 ────────────────────────────────────────────────────────────────
 ●  web-client       Working    Read    4s      █▌   RAM  0.8G
 ◐  data-pipeline    Shell      Bash   31s      █▍   RAM  0.7G
 ────────────────────────────────────────────────────────────────
 Memory 15.6/25.8GB · Swap 12.3GB · Agents 3.7GB
```

<img src="docs/images/panel.png" width="425"
     alt="The panel parked on the desktop: 2/4 in the header with the on-top arrow, an approval row and an idle row above the rule, two working rows below it.">

**Clicking it never takes the front.** Apart from a row sending you to its terminal, the editor you
were in stays where it was. This app has no Dock icon, so a window that comes to the front has no
way back.

**Drag it anywhere on its body** to move it, and the spot is remembered. It sizes itself to its
contents but **keeps the corner you parked it in** — park it bottom-right and it grows upward as
sessions appear. Only when it would outgrow the screen does it scroll inside itself.

**Right-click the header** (`2/5`) for the handles. The `▲`/`△` at the top right tells you whether
it is currently on top.

| Handle | What it does |
|---|---|
| Always on top | Off, it sinks behind other windows like a normal one. The way back is in the menu bar |
| Waiting only | Keeps just the rows that need you, and the window narrows to match |
| Close | Same as **Hide panel** in the menu bar |

**A background session can be stopped from here.** Right-click one of the rows a click cannot
move — a daemon holds their pty, so no terminal window exists to go to — and the menu offers to
stop it. The two sets are exactly the same rows, turned around: the one you could never reach is
the one you can now end.

It asks the CLI (`claude stop`) instead of killing the process, so a transcript is not cut
mid-write and the conversation survives — `claude attach <id>` opens it again. While it winds
down the row says **Stopping…** where its metrics were, then leaves the list.

**Its look is yours to choose,** in Settings → Panel: a backdrop — blur or solid, at any opacity
down to none at all, which leaves the text on the desktop with no plate behind it — plus text
size, row density and the margin around the list. None is clean over a wallpaper and tangles with
the text behind it over another window, which the setting says next to the choice rather than
after you make it.

Three **skins** dress the same rows without moving anything. **Simple** keeps every row at one
weight. **Bold** puts the name first and lets status and metrics fall back. **Quiet** holds only
the rows that need you and sinks the rest toward the background — this app's whole argument,
drawn.

While the pointer is over the panel the list holds still. Waiting rows sort to the top, so an
unfrozen list would move the row you were reaching for out from under you.

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

**Menu bar** — the count. Click for the list, or **Show panel** to park it in a corner. `⌘,` opens
settings.

**Settings** has four tabs:

- **Display** — language, appearance (follow the system, or pin it light or dark), line layout,
  which columns to show, whether hovering a row says why it is waiting, which of the three metrics
  to show (RAM bar, RAM GB, CPU % — each on its own switch), whether recording is on, whether
  pointing at the menu bar count opens the list without a click, refresh interval, how the source
  is written into the name, and how long a finished codex app thread stays listed. A live preview
  renders real sessions through the same code the menu uses, so what you see is what you get.

  <img src="docs/images/settings-display.png" width="620"
       alt="The Display tab of Settings, with rows for language, appearance, row layout, metrics, recording, refresh, open on hover, source label and codex app threads.">

- **Panel** — show it, always on top, waiting only, and how it looks: backdrop style and opacity,
  text size, row density, the margin around the list, and the skin. Everything on this tab touches
  the panel alone — the menu does not change.
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
Columns are placed by measured glyph width rather than by counting cells, so a row holds its
columns whether the names are Latin or Hangul.

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
By hour
  Hour       at desk     sess      run    queue 2+
  10:00         1.1h      5.0      1.9         58%
  22:00         0.3h      6.0      0.4         96%
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

- **Session status comes from an undocumented internal file.** Observed on Claude Code 2.1.263 and
  2.1.267. If the format changes this breaks; there is a fallback that reads the transcript
  instead, and rows using it are marked as estimates rather than failing silently.
- **Half of what it watches writes no status down.** Claude Code in a terminal and codex threads in
  the ChatGPT app record their own state; the Claude desktop app and terminal codex record none, so
  those rows are read off the end of the transcript and carry an estimate mark. An app thread has no
  process of its own, so it shows no memory or CPU and cannot be told apart from one still open —
  only recently finished threads are listed. Of terminal codex it takes the interactive session
  (`codex-tui`) alone; `codex exec` has nobody sitting in front of it to wait for.
- **Terminal.app only** for the jump-to-terminal feature. iTerm2, Ghostty, WezTerm and kitty each
  need their own automation path. Inside tmux it reaches the window but not the pane.
  On another terminal a row click cannot move anything, but it **says why** — in the clicked row
  for three seconds in the panel, and in a dialog from the menu.
- **A background session has nowhere to go.** It runs on a pty the daemon made, so no terminal
  window exists for it. Those rows are shown as **not clickable** — being unable to click is more
  honest than clicking and having nothing happen. From the panel you can right-click one and stop
  it, which is the one thing that row can still do for you.
- **Servers a session spawned can escape its total.** A dev server or container that detaches from
  the process tree is not counted in that session. The memory tab lists them separately, and says
  "multiple sessions (n)" rather than guessing when several sessions share a project.
- **Unsigned.** Releases are not signed or notarised, so macOS blocks the first launch.
- **macOS only**, universal (Apple Silicon and Intel), built against the macOS 13 SDK but only run
  on macOS 26.

## License

MIT — see [LICENSE](LICENSE).
