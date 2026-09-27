#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v love >/dev/null 2>&1; then
    echo "❌ Love2D (love) não encontrado no PATH."
    echo "Instale através de https://love2d.org ou via gerenciador de pacotes."
    exit 1
fi

echo "🎮 Starting Loci Arena Love2D client..."
exec love "$ROOT_DIR/client" "$@"
