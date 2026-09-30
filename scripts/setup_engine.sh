#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
TARGET_BIN="$BIN_DIR/loci2d"
VERSION="$(cat "$ROOT_DIR/.loci2d-version" 2>/dev/null || echo "latest")"
FORCE_DOWNLOAD=false

if [ "$1" = "--download" ] || [ "$1" = "-d" ] || [ "$1" = "--force" ]; then
    FORCE_DOWNLOAD=true
fi

mkdir -p "$BIN_DIR"

echo "=== Loci Arena - Engine Setup (${VERSION}) ==="

# 1. Check if loci2d binary already exists and works (unless force download)
if [ "$FORCE_DOWNLOAD" = false ] && [ -f "$TARGET_BIN" ] && [ -x "$TARGET_BIN" ]; then
    echo "[OK] Found existing loci2d binary at bin/loci2d"
    echo "Tip: Run './scripts/setup_engine.sh --download' to force downloading the latest GitHub release."
    exit 0
fi

# 2. Check local sibling repository (common during local engine development)
if [ "$FORCE_DOWNLOAD" = false ]; then
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
fi

# 3. Detect Platform and Download from GitHub Releases
OS_TYPE="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_TYPE="$(uname -m)"

case "$OS_TYPE" in
    linux*)
        PATTERN="loci2d-linux-x86_64"
        ;;
    darwin*)
        PATTERN="loci2d-macos-arm64"
        ;;
    msys*|mingw*|cygwin*)
        PATTERN="loci2d-windows-x86_64.exe"
        TARGET_BIN="$BIN_DIR/loci2d.exe"
        ;;
    *)
        PATTERN="loci2d-linux-x86_64"
        ;;
esac

echo "-> Downloading ${VERSION} (${PATTERN}) from GitHub (Loci2D/loci2d)..."

# Try gh CLI if installed
if command -v gh >/dev/null 2>&1; then
    if gh release download "$VERSION" --repo Loci2D/loci2d --pattern "$PATTERN" --clobber -O "$TARGET_BIN" 2>/dev/null; then
        chmod +x "$TARGET_BIN"
        echo "[OK] Downloaded loci2d binary successfully via GitHub CLI!"
        exit 0
    fi
fi

# Fallback to curl
DOWNLOAD_URL="https://github.com/Loci2D/loci2d/releases/download/${VERSION}/${PATTERN}"
if command -v curl >/dev/null 2>&1; then
    if curl -sSL -f "$DOWNLOAD_URL" -o "$TARGET_BIN"; then
        chmod +x "$TARGET_BIN"
        echo "[OK] Downloaded loci2d binary successfully via curl!"
        exit 0
    fi
fi

# 4. Fallback instructions if download failed
echo ""
echo "Aviso: Nao foi possivel baixar o binario loci2d automaticamente."
echo "Para compilar localmente caso voce tenha o repositorio clonado:"
echo "   cd ../loci2d && cargo build --release"
echo "   cp target/release/loci2d $TARGET_BIN"
echo ""
exit 1
