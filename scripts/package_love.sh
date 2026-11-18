#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT_DIR/client"
OUT_FILE="${1:-$ROOT_DIR/dist/game.love}"

if [ ! -d "$CLIENT_DIR/loci2d" ]; then
    echo "-> client/loci2d nao encontrado. Executando setup_sdk.sh --download..."
    "$ROOT_DIR/scripts/setup_sdk.sh" --download
fi

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

# Copy client dereferencing symlinks (e.g. client/loci2d -> ../sdk-love2d)
cp -RL "$CLIENT_DIR" "$STAGE_DIR/client"

# Remove desktop-only binaries, backups, logs, docs and git metadata
rm -rf \
    "$STAGE_DIR/client/loci2d.bak" \
    "$STAGE_DIR/client/loci2d/.git" \
    "$STAGE_DIR/client/loci2d/.github" \
    "$STAGE_DIR/client/loci2d/docs" \
    "$STAGE_DIR/client/loci2d/examples" \
    "$STAGE_DIR/client/loci2d/logs" \
    "$STAGE_DIR/client/loci2d/test_sdk.lua" \
    "$STAGE_DIR/client/loci2d/lib/src"
find "$STAGE_DIR/client" -type f \( -name "*.so" -o -name "*.dll" -o -name "*.dylib" -o -name "*.log" -o -name ".DS_Store" \) -delete

mkdir -p "$(dirname "$OUT_FILE")"
rm -f "$OUT_FILE"

(
    cd "$STAGE_DIR/client"
    zip -9 -q -r "$OUT_FILE" .
)

echo "[OK] Pacote Love2D gerado em: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
