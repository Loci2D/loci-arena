#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
TARGET_BIN="$BIN_DIR/loci2d"
VERSION="$(cat "$ROOT_DIR/.loci2d-version" 2>/dev/null || echo "latest")"

mkdir -p "$BIN_DIR"

echo "=== Loci Arena - Engine Setup (${VERSION}) ==="

# 1. Check if loci2d binary already exists and works
if [ -f "$TARGET_BIN" ] && [ -x "$TARGET_BIN" ]; then
    echo "[OK] Found existing loci2d binary at bin/loci2d"
    exit 0
fi

# 2. Check local sibling repository (common during development)
LOCAL_LOCI_RELEASE="$ROOT_DIR/../loci2d/target/release/loci2d"
LOCAL_LOCI_DEBUG="$ROOT_DIR/../loci2d/target/debug/loci2d"

if [ -f "$LOCAL_LOCI_RELEASE" ]; then
    echo "-> Copying loci2d release binary from local repo: $LOCAL_LOCI_RELEASE"
    cp "$LOCAL_LOCI_RELEASE" "$TARGET_BIN"
    chmod +x "$TARGET_BIN"
    echo "[OK] Engine configured successfully from local build!"
    exit 0
elif [ -f "$LOCAL_LOCI_DEBUG" ]; then
    echo "-> Copying loci2d debug binary from local repo: $LOCAL_LOCI_DEBUG"
    cp "$LOCAL_LOCI_DEBUG" "$TARGET_BIN"
    chmod +x "$TARGET_BIN"
    echo "[OK] Engine configured successfully from local debug build!"
    exit 0
fi

# 3. Detect Platform and Download from GitHub Releases
OS_TYPE="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_TYPE="$(uname -m)"

case "$OS_TYPE" in
    linux*)
        PATTERN="loci2d-linux-x86_64"
        ;;
    darwin*)
        if [ "$ARCH_TYPE" = "arm64" ]; then
            PATTERN="loci2d-macos-arm64"
        else
            PATTERN="loci2d-macos-x86_64"
        fi
        ;;
    msys*|mingw*|cygwin*)
        PATTERN="loci2d-windows-x86_64.exe"
        TARGET_BIN="$BIN_DIR/loci2d.exe"
        ;;
    *)
        PATTERN="loci2d-linux-x86_64"
        ;;
esac

echo "-> Attempting to download ${VERSION} (${PATTERN}) from GitHub (Loci2D/loci2d)..."
if command -v gh >/dev/null 2>&1; then
    if gh release download "$VERSION" --repo Loci2D/loci2d --pattern "$PATTERN" -O "$TARGET_BIN" 2>/dev/null; then
        chmod +x "$TARGET_BIN"
        echo "[OK] Downloaded loci2d binary successfully!"
        exit 0
    fi
fi

# 4. Fallback instructions if binary is not yet published
echo ""
echo "Aviso: loci2d binary not found automatically."
echo "Para compilar localmente caso você tenha o repositório da engine clonado:"
echo "   cd ../loci2d && cargo build --release"
echo "   cp target/release/loci2d $TARGET_BIN"
echo ""
exit 1
