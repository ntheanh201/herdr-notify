---
name: herdr-notify
description: >-
  Install, verify, and troubleshoot herdr-notify — native macOS notifications
  for Herdr with click-to-focus. Use when Herdr toasts show up as "Script
  Editor", when Herdr notifications play a sound but display no banner, when
  notifications appear but clicking them doesn't jump to the firing pane, when
  installing or reinstalling herdr-notify, or when changing its icon emoji.
  Also use when diagnosing terminal-notifier on macOS 11+.
allowed-tools: Bash, Read, Edit
---

# herdr-notify

Native macOS notifications for Herdr. Replaces the two broken paths behind Herdr's
`delivery = "system"` setting.

## Background you need

Herdr's `system` delivery runs whatever `terminal-notifier` it finds on `PATH`, and falls back
to `osascript -e 'display notification …'` otherwise.

- **Homebrew's `terminal-notifier` 2.0.0** links the deprecated `NSUserNotification` API. On
  macOS 11+ the notification is accepted and its sound plays, but **no banner renders and
  nothing reaches Notification Center**. It fails silently — `terminal-notifier -list ALL` still
  reports the notification as delivered, which makes this very easy to misdiagnose.
- **The `osascript` fallback** works but macOS attributes it to **Script Editor**.

`herdr-notify` installs a `UNUserNotification`-based app bundle plus a shim that takes the
`terminal-notifier` name, so Herdr routes to it.

## Diagnose first

Do not install anything before establishing which failure this is.

```sh
sw_vers -productVersion                  # NSUserNotification is dead on 11+
command -v terminal-notifier             # which notifier, if any, Herdr will find
brew list terminal-notifier 2>/dev/null  # the broken one, if present
grep -A2 'ui.toast' ~/.config/herdr/config.toml
tail -5 ~/.local/share/herdr-notify.log 2>/dev/null   # only exists once installed
```

Map the symptom:

| Symptom | Cause |
| --- | --- |
| Banner says "Script Editor" | Herdr fell back to osascript — the shim is missing, or the notifier exited non-zero |
| Sound plays, nothing visible, Notification Center empty | Homebrew's `terminal-notifier` is winning on `PATH` |
| No banner and no sound | Check System Settings → Notifications; also confirm `delivery` isn't `"off"` |
| Banner fine, click does nothing useful | Expected for hand-fired `herdr notification show`; only agent-state toasts carry a pane target |

## Install

```sh
git clone https://github.com/ntheanh201/herdr-notify.git
cd herdr-notify
./install.sh          # or: ./install.sh 🐕  to pick the icon emoji
```

`install.sh` builds `~/Applications/Herdr Notify.app`, installs the shim to
`~/.local/bin/terminal-notifier`, and warns about `PATH` problems and a conflicting Homebrew
`terminal-notifier`. Requires the Xcode command line tools (`xcode-select --install`).

Then ensure `~/.config/herdr/config.toml` contains:

```toml
[ui.toast]
delivery = "system"
```

and apply it:

```sh
herdr server reload-config
```

## Verify

```sh
herdr notification show "test" --body "hello"
sleep 1
tail -1 ~/.local/share/herdr-notify.log
"$HOME/Applications/Herdr Notify.app/Contents/MacOS/herdr-notify" -list ALL | tail -2
```

A log line proves Herdr called the shim; a `-list ALL` row proves macOS accepted the
notification. **Ask the user what they actually saw on screen** — delivery succeeding and a
banner being visible are different things, and only the user can confirm the second.

Test the body-less case too, since it exercises a different code path:

```sh
herdr notification show "test"
```

## Critical gotchas

- **Empty `-message`.** Herdr passes an empty `-message` for body-less toasts. Any non-zero exit
  from the notifier sends Herdr to the osascript fallback, so a title-only notification must be
  accepted, not rejected. If you fork `main.swift`, preserve this.
- **`herdr pane focus` is directional** (`--direction left|down|…`) and cannot target by id. The
  by-id call is `herdr agent focus <pane_id>`.
- **A click-launched app inherits a bare `PATH`** (`/usr/bin:/bin:/usr/sbin:/sbin`), so GUI mode
  can't find `herdr` by scanning it. CLI mode records the resolved path in the notification's
  `userInfo`; `$HERDR_BIN` and common install locations are the fallbacks.
- **The Herdr server captures `PATH` at launch.** After editing a shell profile, restart the
  server or it still won't find the shim.
- **Restarting the Herdr server exits every pane process.** Never run `herdr server stop`
  from inside a Herdr pane — you will kill your own session. Tell the user to run it from a
  plain terminal window after detaching.
- **macOS caches notification icons.** `killall usernoted` forces a refresh after an icon change.

## Alternative worth offering

If the user only wants working notifications and doesn't care about the icon or click-to-focus,
`delivery = "terminal"` needs none of this — Herdr emits OSC 9 and the host terminal (Ghostty,
WezTerm, kitty) raises the notification under its own identity. Only `system` mode plus this
project gets a custom icon and a click that jumps to the firing pane.
