#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
LINUX_BINARY="$BUILD_DIR/linux/gecko.x86_64"
WIN_BINARY="$BUILD_DIR/win/gecko.exe"
MAC_BINARY="$BUILD_DIR/mac/gecko.zip"

GODOT="${GODOT:-$HOME/.local/bin/godot}"

# Toggle which platforms to build (edit these)
BUILD_WIN=true
BUILD_LINUX=true
BUILD_MAC=false

# itch.io: set ITCH_TARGET to push built platforms to itch (default: kwakuuuu/gecko)
ITCH_TARGET="${ITCH_TARGET:-kwakuuuu/gecko}"

if [[ ! -x "$GODOT" ]]; then
    echo "Error: Godot not found at $GODOT"
    echo "Set GODOT env var to your Godot 4.6 binary path."
    exit 1
fi

rm -rf "$BUILD_DIR"

mkdir -p "$BUILD_DIR/linux" "$BUILD_DIR/win" "$BUILD_DIR/mac"

MODE="${1:-debug}"

build_preset() {
    local preset="$1" binary="$2" flag="$3"
    echo "--- Building $preset ($MODE) ---"
    if "$GODOT" --headless --path "$PROJECT_DIR" "$flag" "$preset" "$binary" 2>&1; then
        echo "  OK: $binary"
    else
        echo "  WARN: $preset build failed"
        return 1
    fi
}

case "$MODE" in
    debug)
        flag="--export-debug"
        ;;
    release)
        flag="--export-release"
        ;;
    run)
        echo "Skipping build, running existing binary..."
        if [[ -f "$LINUX_BINARY" ]]; then
            exec "$LINUX_BINARY"
        else
            echo "Error: No Linux binary at $LINUX_BINARY"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [debug|release|run]"
        exit 1
        ;;
esac

if [[ "$MODE" != "run" ]]; then
    if [[ "$BUILD_LINUX" == true ]]; then
        build_preset "Linux" "$LINUX_BINARY" "$flag" || true
        if [[ -n "${ITCH_TARGET:-}" && -f "$LINUX_BINARY" ]] && command -v butler &>/dev/null; then
            echo "--- Pushing to itch.io (linux) ---"
            butler push "$BUILD_DIR/linux" "$ITCH_TARGET:linux"
            echo "  OK: pushed to $ITCH_TARGET:linux"
        fi
    fi
    if [[ "$BUILD_WIN" == true ]]; then
        build_preset "Windows Desktop" "$WIN_BINARY" "$flag" || true
        if [[ -n "${ITCH_TARGET:-}" && -f "$WIN_BINARY" ]] && command -v butler &>/dev/null; then
            echo "--- Pushing to itch.io (exe only) ---"
            tmpdir=$(mktemp -d)
            cp "$WIN_BINARY" "$tmpdir/"
            butler push "$tmpdir" "$ITCH_TARGET:windows"
            rm -rf "$tmpdir"
            echo "  OK: pushed to $ITCH_TARGET:windows"
        fi
    fi
    if [[ "$BUILD_MAC" == true ]]; then
        build_preset "macOS" "$MAC_BINARY" "$flag" || true
        if [[ -n "${ITCH_TARGET:-}" && -f "$MAC_BINARY" ]] && command -v butler &>/dev/null; then
            echo "--- Pushing to itch.io (macOS app only) ---"
            tmpdir=$(mktemp -d)
            cp "$MAC_BINARY" "$tmpdir/"
            butler push "$tmpdir" "$ITCH_TARGET:osx"
            rm -rf "$tmpdir"
            echo "  OK: pushed to $ITCH_TARGET:osx"
        fi
    fi
fi
