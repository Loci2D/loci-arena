#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT_DIR/client"
TARGET_DIR="$CLIENT_DIR/loci2d"
SDK_VERSION="$(cat "$ROOT_DIR/.loci2d-sdk-version" 2>/dev/null || echo "v0.6.1")"
ENGINE_VERSION="$(cat "$ROOT_DIR/.loci2d-version" 2>/dev/null || echo "latest")"
FORCE_DOWNLOAD=false

if [ "$1" = "--download" ] || [ "$1" = "-d" ] || [ "$1" = "--force" ]; then
    FORCE_DOWNLOAD=true
fi

echo "=== Loci Arena - Client SDK Setup (${SDK_VERSION}) ==="

# 0. SemVer Compatibility Verification
if [ -f "$ROOT_DIR/.loci2d-version" ] && [ -f "$ROOT_DIR/.loci2d-sdk-version" ]; then
    ENG_MM="$(echo "$ENGINE_VERSION" | sed 's/^v//' | cut -d. -f1,2)"
    SDK_MM="$(echo "$SDK_VERSION" | sed 's/^v//' | cut -d. -f1,2)"
    if [ "$ENG_MM" != "$SDK_MM" ]; then
        echo "⚠️  AVISO DE COMPATIBILIDADE:"
        echo "   Engine está na versão: $ENGINE_VERSION ($ENG_MM)"
        echo "   SDK está configurado para: $SDK_VERSION ($SDK_MM)"
        echo "   Recomenda-se alinhar Major.Minor para evitar rejeição de protocolo."
        echo ""
    fi
fi

# 1. Local Sibling Repository Detection (Developer DX Mode)
LOCAL_SDK="${LOCI_SDK_DIR:-$ROOT_DIR/../sdk-love2d}"

if [ "$FORCE_DOWNLOAD" = false ] && [ -d "$LOCAL_SDK" ]; then
    echo "-> Repositorio local do SDK detectado em: $LOCAL_SDK"

    # Pre-compile native pb.so locally if needed and gcc is available
    if [ ! -f "$LOCAL_SDK/lib/pb.so" ] && [ -f "$LOCAL_SDK/lib/src/pb.c" ] && command -v gcc >/dev/null 2>&1; then
        echo "-> Compilando lua-protobuf nativo (pb.so) no SDK local..."
        INC_DIR="$LOCAL_SDK/lib/src/include"
        [ ! -d "$INC_DIR" ] && INC_DIR="/usr/include/lua5.1"
        gcc -O2 -shared -fPIC -I"$INC_DIR" "$LOCAL_SDK/lib/src/pb.c" -o "$LOCAL_SDK/lib/pb.so" 2>/dev/null || true
    fi

    # Backup existing client/loci2d if it's a real folder (not a symlink)
    if [ -d "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]; then
        echo "-> Movendo pasta legada client/loci2d para client/loci2d.bak"
        rm -rf "$CLIENT_DIR/loci2d.bak"
        mv "$TARGET_DIR" "$CLIENT_DIR/loci2d.bak"
    fi

    mkdir -p "$CLIENT_DIR"
    # Create or update symbolic link
    ln -sfn "$LOCAL_SDK" "$TARGET_DIR"
    echo "[OK] SDK configurado via link simbolico com sucesso!"
    echo "     client/loci2d -> $LOCAL_SDK"
    echo "     (Todas as alteracoes feitas no sdk-love2d refletem instantaneamente no client)"
    echo "Dica: Execute './scripts/setup_sdk.sh --download' se quiser baixar o bundle oficial do GitHub."
    exit 0
fi

# 2. Download from GitHub Releases
echo "-> Baixando SDK ${SDK_VERSION} oficial do GitHub (Loci2D/sdk-love2d)..."

ZIP_NAME="loci2d-sdk-love2d.zip"
TMP_ZIP="/tmp/loci2d-sdk-$$.zip"
TMP_EXTRACT="/tmp/loci2d-sdk-extract-$$"
DOWNLOAD_SUCCESS=false

# Try GitHub CLI (gh)
if command -v gh >/dev/null 2>&1; then
    if gh release download "$SDK_VERSION" --repo Loci2D/sdk-love2d --pattern "$ZIP_NAME" --clobber -O "$TMP_ZIP" 2>/dev/null; then
        DOWNLOAD_SUCCESS=true
        echo "[OK] Arquivo baixado via GitHub CLI."
    fi
fi

# Fallback to curl
if [ "$DOWNLOAD_SUCCESS" = false ] && command -v curl >/dev/null 2>&1; then
    DOWNLOAD_URL="https://github.com/Loci2D/sdk-love2d/releases/download/${SDK_VERSION}/${ZIP_NAME}"
    if curl -sSL -f "$DOWNLOAD_URL" -o "$TMP_ZIP"; then
        DOWNLOAD_SUCCESS=true
        echo "[OK] Arquivo baixado via curl."
    fi
fi

if [ "$DOWNLOAD_SUCCESS" = true ]; then
    mkdir -p "$TMP_EXTRACT"
    unzip -q -o "$TMP_ZIP" -d "$TMP_EXTRACT"

    # Remove existing symlink or folder
    rm -rf "$TARGET_DIR"
    mkdir -p "$CLIENT_DIR"

    if [ -d "$TMP_EXTRACT/loci2d" ]; then
        mv "$TMP_EXTRACT/loci2d" "$TARGET_DIR"
    else
        mv "$TMP_EXTRACT" "$TARGET_DIR"
    fi

    rm -rf "$TMP_ZIP" "$TMP_EXTRACT"
    echo "[OK] SDK (${SDK_VERSION}) instalado com sucesso em client/loci2d a partir do GitHub Releases!"
    exit 0
fi

echo ""
echo "Aviso: Nao foi possivel baixar o release oficial do SDK (${SDK_VERSION}) nem encontrar repo local."
echo "Certifique-se de clonar o repositorio 'sdk-love2d' ao lado de loci-arena:"
echo "   cd .. && git clone git@github.com:Loci2D/sdk-love2d.git"
echo "   ./scripts/setup_sdk.sh"
echo ""
exit 1
