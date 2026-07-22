# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-22

### Added

- `skills/herdr-notify/` — an installable agent skill. Copy it to `~/.claude/skills/` and an
  agent can diagnose, install, and troubleshoot this on your machine. It leads with diagnosis,
  since "Herdr never called the notifier" and "the notifier was called and failed" look
  identical from the outside but need opposite fixes.
- `AGENTS.md` — build and verification loop for agents contributing to this repo, plus the five
  invariants that silently revert users to Script Editor banners when broken. `CLAUDE.md`
  points at it.

## [1.0.0] - 2026-07-22

Initial release. Verified against Herdr 0.7.5 on macOS 15.7.5.

### Added

- `UNUserNotification`-based notifier in an ad-hoc signed app bundle, so macOS grants it real
  notification authorization and shows banners as **Herdr** rather than *Script Editor*.
- Click a banner to focus the pane that fired it. Notifications are tagged at post time with the
  `pane_id` of the agent holding the highest `state_change_seq`; clicking runs
  `herdr agent focus <pane_id>`, which switches workspace and tab as needed.
- Emoji app icon, rendered at all ten required sizes — `./install.sh 🐕` to change it.
- `install.sh`: builds the bundle, installs the `terminal-notifier` shim Herdr probes for, and
  checks the environment (`PATH`, a conflicting Homebrew `terminal-notifier`, the `config.toml`
  `delivery` setting).
- terminal-notifier flag compatibility for the subset Herdr uses: `-title`, `-message`,
  `-subtitle`, `-sound`, `-group`, `-activate`, plus `-list` and `-remove`.
- Invocation logging to `~/.local/share/herdr-notify.log`, which distinguishes "Herdr never
  called us" from "we were called and failed". Disable with `HERDR_NOTIFY_LOG=0`.

### Notes

- Herdr passes an **empty** `-message` for body-less toasts (`herdr notification show "title"`),
  and any non-zero exit sends Herdr to its osascript fallback. Title-only notifications are
  therefore accepted rather than rejected.
- A click-launched app inherits a bare `PATH`, so the resolved `herdr` path is recorded in the
  notification's `userInfo`; `$HERDR_BIN` and common install locations are the fallbacks.
- Herdr's lookup of the `terminal-notifier` command name is an undocumented implementation
  detail, not a supported extension point. If a future Herdr release changes it, banners will
  silently revert to Script Editor and the shim log will go quiet.

[1.1.0]: https://github.com/ntheanh201/herdr-notify/releases/tag/v1.1.0
[1.0.0]: https://github.com/ntheanh201/herdr-notify/releases/tag/v1.0.0
