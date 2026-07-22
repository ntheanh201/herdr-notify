#!/bin/sh
# One-shot setup: build the app, install the `terminal-notifier` shim Herdr looks for,
# and report anything left to do by hand.
#
#   ./install.sh          install with the default icon
#   ./install.sh 🐕       install with a different icon emoji
#
set -eu

EMOJI="${1:-🐑}"
SRC="$(cd "$(dirname "$0")" && pwd)"
SHIM_DIR="$HOME/.local/bin"
SHIM="$SHIM_DIR/terminal-notifier"
CONFIG="$HOME/.config/herdr/config.toml"

command -v swiftc >/dev/null 2>&1 || {
    echo "error: swiftc not found. Install the Xcode command line tools:" >&2
    echo "  xcode-select --install" >&2
    exit 1
}

sh "$SRC/build.sh" "$EMOJI"

# --- the shim -------------------------------------------------------------
# Herdr's `system` delivery runs whatever `terminal-notifier` it finds on PATH.
# We take that name so Herdr routes to us instead of the osascript fallback.

if [ -e "$SHIM" ] && ! grep -q "Herdr Notify.app" "$SHIM" 2>/dev/null; then
    echo "==> backing up existing $SHIM to $SHIM.bak"
    mv "$SHIM" "$SHIM.bak"
fi

mkdir -p "$SHIM_DIR"
cat > "$SHIM" <<'SHIMEOF'
#!/bin/sh
# Routes Herdr's `delivery = "system"` toasts to "Herdr Notify.app".
# Installed by https://github.com/ntheanh201/herdr-notify
#
# The log is the fastest way to tell "Herdr never called us" apart from
# "we were called and failed". Set HERDR_NOTIFY_LOG=0 to disable it.
if [ "${HERDR_NOTIFY_LOG:-1}" != "0" ]; then
    mkdir -p "$HOME/.local/share" 2>/dev/null
    echo "$(date '+%Y-%m-%dT%H:%M:%S') invoked: $*" >> "$HOME/.local/share/herdr-notify.log" 2>/dev/null
fi
exec "$HOME/Applications/Herdr Notify.app/Contents/MacOS/herdr-notify" "$@"
SHIMEOF
chmod +x "$SHIM"
echo "==> installed shim at $SHIM"

# --- checks ---------------------------------------------------------------

case ":$PATH:" in
    *":$SHIM_DIR:"*) ;;
    *)
        echo
        echo "WARNING: $SHIM_DIR is not on your PATH, so Herdr will not find the shim."
        echo "Add this to your shell profile and restart the Herdr server:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac

if brew list terminal-notifier >/dev/null 2>&1; then
    echo
    echo "WARNING: Homebrew's terminal-notifier is installed and may shadow the shim."
    echo "It is broken on macOS 11+ regardless (see README). Remove it with:"
    echo "  brew uninstall terminal-notifier"
fi

if [ -f "$CONFIG" ] && grep -q 'delivery *= *"system"' "$CONFIG"; then
    echo "==> $CONFIG already uses delivery = \"system\""
else
    echo
    echo "Last step — set this in $CONFIG:"
    echo
    echo "  [ui.toast]"
    echo "  delivery = \"system\""
    echo
    echo "then apply it with:  herdr server reload-config"
fi

echo
echo "Test with:  herdr notification show \"test\" --body \"hello\""
