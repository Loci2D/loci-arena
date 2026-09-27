#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="$ROOT_DIR/bin/loci2d"

if [ ! -f "$BIN_PATH" ]; then
    echo "loci2d binary not found at bin/loci2d. Running setup..."
    "$ROOT_DIR/scripts/setup_engine.sh"
fi

echo "Starting loci2d server for Loci Arena..."
cd "$ROOT_DIR/server"
exec "$BIN_PATH" --scripts-dir "$ROOT_DIR/server/scripts" "$@"
