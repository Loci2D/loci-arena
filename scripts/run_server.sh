#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="$ROOT_DIR/bin/loci2d"
EXPECTED_VER="$(cat "$ROOT_DIR/.loci2d-version" 2>/dev/null | tr -d '[:space:]')"
INSTALLED_VER="$(cat "$ROOT_DIR/bin/loci2d.version" 2>/dev/null | tr -d '[:space:]')"

if [ ! -f "$BIN_PATH" ] || [ "$INSTALLED_VER" != "$EXPECTED_VER" ]; then
    echo "loci2d binary missing or outdated (${INSTALLED_VER:-none} != ${EXPECTED_VER}). Running setup..."
    "$ROOT_DIR/scripts/setup_engine.sh"
fi

echo "Starting loci2d server for Loci Arena..."
cd "$ROOT_DIR/server"
exec "$BIN_PATH" --scripts-dir "$ROOT_DIR/server/scripts" "$@"
