# AGENTS.md

Guidance for coding agents working on this repository. Humans should read
[README.md](README.md) first — this file covers only what an agent needs to change code here
safely.

## What this is

A macOS notifier that Herdr invokes through its `delivery = "system"` toast path. Two Swift
files, two shell scripts, no package manager and no dependencies beyond the system frameworks.

| File | Purpose |
| --- | --- |
| `main.swift` | The notifier. CLI mode posts a notification; GUI mode handles a banner click. |
| `makeicon.swift` | Renders an emoji into a macOS `.iconset`. |
| `build.sh` | Compile, generate icon, assemble bundle, ad-hoc sign, register. |
| `install.sh` | `build.sh` plus the `terminal-notifier` shim, with environment checks. |
| `skills/herdr-notify/` | An installable agent skill for setting this up on someone's machine. |

## Build and verify

```sh
./build.sh                  # compile + install to ~/Applications/Herdr Notify.app
sh -n build.sh install.sh   # shell syntax check
```

There is no unit test suite — the behaviour under test is "macOS renders a banner", which
can't be asserted from a terminal. Verify a change like this:

```sh
herdr notification show "test" --body "hello"   # with a body
herdr notification show "test"                  # WITHOUT a body — different code path
sleep 1
tail -2 ~/.local/share/herdr-notify.log
"$HOME/Applications/Herdr Notify.app/Contents/MacOS/herdr-notify" -list ALL | tail -3
```

A shim log line proves Herdr invoked us. A `-list ALL` row proves macOS accepted the
notification. **Neither proves a banner appeared** — only the user can confirm that, so ask
rather than claiming success. CI (`.github/workflows/build.yml`) covers compilation, icon
generation, bundle assembly, signing, and shell syntax; it cannot cover rendering.

## Invariants — breaking these silently reverts users to Script Editor banners

1. **Never exit non-zero for a title-only notification.** Herdr passes an empty `-message` for
   `herdr notification show "title"`, and any non-zero exit makes Herdr fall back to osascript,
   which macOS attributes to Script Editor. This is the single easiest way to break the project
   in a way that looks like it isn't installed at all.
2. **Keep the executable reachable under the name `terminal-notifier`.** That command name is
   Herdr's only lookup, hardcoded — there is no config setting for a custom notifier.
3. **Don't assume `PATH` in GUI mode.** A click-launched app gets `/usr/bin:/bin:/usr/sbin:/sbin`.
   Resolve `herdr` via `userInfo["herdr_bin"]`, then `$HERDR_BIN`, then known locations.
4. **Use `herdr agent focus <pane_id>` to focus by id.** `herdr pane focus` is directional
   (`--direction`) and cannot target a pane by id.
5. **Keep the flag surface terminal-notifier-compatible** for what Herdr sends: `-title`,
   `-message`, `-subtitle`, `-sound`, `-group`, `-activate`, plus `-list` and `-remove`.
   Unknown flags must be ignored, never fatal.

## Environment notes

- Requires macOS 11+ and `swiftc` from the Xcode command line tools.
- The bundle is **ad-hoc signed** (`codesign --sign -`). It works locally but would be
  Gatekeeper-quarantined if downloaded, which is why releases ship no binary.
- `lsregister` is best-effort — it must never fail the build, since it's meaningless on CI.
- **Never run `herdr server stop` from inside a Herdr pane.** It exits every pane process,
  including the agent session running the command.

## Conventions

- Commits are signed off (`git commit -s`).
- Comments explain *why*, particularly where behaviour is dictated by an undocumented Herdr
  or macOS detail. Those comments are load-bearing — a future reader has no other source.
- Update `CHANGELOG.md` for user-visible changes; the project follows SemVer.
