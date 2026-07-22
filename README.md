# herdr-notify

Native macOS notifications for [Herdr](https://herdr.dev) — with the right app name, your own
icon, and **click a banner to jump straight to the pane that fired it**.

<!-- Replace with a screenshot of a banner if you like: ![banner](docs/banner.png) -->

## The problem

Herdr's `delivery = "system"` toasts shell out to `terminal-notifier` if it's on `PATH`, and
fall back to `osascript -e 'display notification …'` otherwise. On a current macOS, both are bad:

| Path | What you get |
| --- | --- |
| `terminal-notifier` 2.0.0 (Homebrew) | **Nothing.** It links the deprecated `NSUserNotification` API. macOS 11+ accepts the notification and plays its sound, but never renders a banner and never files it in Notification Center. It fails *silently* — `terminal-notifier -list ALL` even reports the notification as delivered. |
| `osascript` fallback | A banner attributed to **Script Editor** — wrong icon, wrong name, and clicking it launches Script Editor. |

`herdr-notify` replaces both with a real `UNUserNotification` client in a signed app bundle, so
macOS grants it proper notification authorization and treats it like any modern app.

## Requirements

- macOS 11 or newer (developed on macOS 15)
- [Herdr](https://herdr.dev)
- Xcode command line tools, for `swiftc` — `xcode-select --install`

## Getting Started

```sh
git clone https://github.com/ntheanh201/herdr-notify.git
cd herdr-notify
./install.sh
```

That builds `~/Applications/Herdr Notify.app`, installs a `terminal-notifier` shim at
`~/.local/bin/terminal-notifier` (the name Herdr probes for), and tells you about anything it
can't do itself — such as `~/.local/bin` missing from your `PATH`, or Homebrew's broken
`terminal-notifier` still being installed and shadowing the shim.

Then point Herdr at the system path, in `~/.config/herdr/config.toml`:

```toml
[ui.toast]
delivery = "system"
```

Apply it and send yourself a test banner:

```sh
herdr server reload-config
herdr notification show "test" --body "hello"
```

You should get a banner titled **test** with the 🐑 icon. If it says *Script Editor*, see
[Troubleshooting](#troubleshooting).

### Pick your own icon

```sh
./install.sh 🐕      # any emoji
```

The emoji is rendered at all ten icon sizes and packed into the bundle. macOS caches
notification icons, so run `killall usernoted` if the old one lingers.

### Uninstall

```sh
rm -rf ~/Applications/"Herdr Notify.app" ~/.local/bin/terminal-notifier
```

and set `delivery` back to `"terminal"` (Herdr's own OSC route) or `"herdr"` (an in-TUI toast).

## How click-to-focus works

Herdr invokes the notifier like this:

```
-title "claude finished" -message "personal · 2 · monorepo" -activate com.mitchellh.ghostty
```

Note it doesn't say which pane. Rather than parse that `workspace · tab · name` body string,
`herdr-notify` asks `herdr agent list` at post time and tags the notification with the `pane_id`
of the agent holding the highest `state_change_seq` — precisely the agent whose state transition
triggered the toast. That id rides along in the notification's `userInfo`.

Clicking a banner makes macOS launch the app with no arguments, which is the signal for GUI
mode: install a `UNUserNotificationCenterDelegate`, read `pane_id` back out of the response, run
`herdr agent focus <pane_id>`, and activate the host terminal. `agent focus` switches workspace
and tab as needed, so the click lands correctly even from another workspace.

Two details worth knowing:

- `herdr pane focus` is **directional** (`--direction left|down|…`) and can't target by id.
  `herdr agent focus <pane_id>` is the by-id call.
- A click-launched app inherits a bare `PATH`, so GUI mode can't find `herdr` by searching it.
  CLI mode records the resolved path in `userInfo`; failing that, `$HERDR_BIN` and a list of
  common install locations are tried.

Hand-fired notifications (`herdr notification show "test"`) have no originating agent, so the
heuristic picks whichever agent last changed state. That's expected — pane targeting only means
something for real agent-state toasts.

## Troubleshooting

**Banners still say "Script Editor".** Herdr fell back to osascript, which means the shim wasn't
found or the notifier exited non-zero. Check `~/.local/share/herdr-notify.log` — the shim logs
every invocation with its arguments. No entry means Herdr never called it: confirm
`command -v terminal-notifier` resolves to the shim, and that the **Herdr server's** `PATH`
includes it (the server captures `PATH` at launch, so restart it after editing your profile).

**Nothing appears at all, but you hear a sound.** That's the signature of Homebrew's
`terminal-notifier` still winning on `PATH`. `brew uninstall terminal-notifier`.

**Notifications are silent and invisible.** Check System Settings → Notifications → Herdr. You
can inspect the raw permission bits with:

```sh
defaults export com.apple.ncprefs - | plutil -convert json - -o - 2>/dev/null
```

**A body-less notification behaves differently.** Herdr passes an *empty* `-message` for
`herdr notification show "title"`. Any non-zero exit from the notifier silently sends Herdr to
the osascript fallback, so the notifier must accept a title-only notification — it does, but
that's the first thing to check if you fork it.

## Files

| File | Purpose |
| --- | --- |
| `main.swift` | The notifier — CLI mode (post a notification) and GUI mode (handle a click) |
| `makeicon.swift` | Renders an emoji into a macOS `.iconset` |
| `build.sh` | Compile, generate icon, assemble bundle, ad-hoc sign, register |
| `install.sh` | `build.sh` plus the shim, with environment checks |

## License

MIT
