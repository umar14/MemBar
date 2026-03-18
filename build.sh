#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# MemBar – build & install script
# Usage:  ./build.sh          → compile & launch
#         ./build.sh install  → also copy to ~/.local/bin + add Login Item
#         ./build.sh remove   → remove login item & binary
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="MemBar"
INSTALL_DIR="$HOME/.local/bin"
BINARY="$INSTALL_DIR/$APP_NAME"

# ── pretty print ─────────────────────────────────────────────────────────────
bold=$(tput bold 2>/dev/null || echo "")
reset=$(tput sgr0 2>/dev/null || echo "")
green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"; cyan="\033[1;36m"

info()  { echo -e "${cyan}▸ $*${reset}"; }
ok()    { echo -e "${green}✔ $*${reset}"; }
warn()  { echo -e "${yellow}⚠ $*${reset}"; }
err()   { echo -e "${red}✘ $*${reset}"; exit 1; }

# ── check Xcode tools ────────────────────────────────────────────────────────
if ! command -v swift &>/dev/null; then
    err "Swift not found. Install Xcode Command Line Tools:  xcode-select --install"
fi

SWIFT_VER=$(swift --version 2>&1 | head -1)
info "Using $SWIFT_VER"

# ── build ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

info "Building $APP_NAME (release)…"
swift build -c release 2>&1 | grep -v "^Build complete" || true

BUILD_BIN=".build/release/$APP_NAME"
[[ -f "$BUILD_BIN" ]] || err "Build failed – binary not found at $BUILD_BIN"
ok "Build succeeded → $BUILD_BIN"

# ── run immediately ───────────────────────────────────────────────────────────
if [[ "${1:-}" != "install" && "${1:-}" != "remove" ]]; then
    info "Launching $APP_NAME (Ctrl-C to stop)…"
    exec "$BUILD_BIN"
fi

# ── install ───────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "install" ]]; then
    mkdir -p "$INSTALL_DIR"
    cp "$BUILD_BIN" "$BINARY"
    chmod +x "$BINARY"
    ok "Installed → $BINARY"

    # Add to PATH hint
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        warn "Add this to your shell config:  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi

    # Login Item via launchd plist
    PLIST_DIR="$HOME/Library/LaunchAgents"
    PLIST="$PLIST_DIR/com.membar.app.plist"
    mkdir -p "$PLIST_DIR"

    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.membar.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/membar.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/membar.err</string>
</dict>
</plist>
PLIST_EOF

    launchctl load "$PLIST" 2>/dev/null && ok "Registered as Login Item (launchd)" \
        || warn "Could not load launchd plist – add $BINARY to Login Items manually in System Settings"

    info "Starting now…"
    open -a Terminal "$BINARY" 2>/dev/null || "$BINARY" &
    ok "Done! MemBar should appear in your menu bar."
fi

# ── remove ────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "remove" ]]; then
    PLIST="$HOME/Library/LaunchAgents/com.membar.app.plist"
    if [[ -f "$PLIST" ]]; then
        launchctl unload "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        ok "Removed launchd Login Item"
    fi
    [[ -f "$BINARY" ]] && rm -f "$BINARY" && ok "Removed binary $BINARY"
    pkill -x MemBar 2>/dev/null && ok "Killed running MemBar instance" || true
    ok "MemBar fully removed."
fi
