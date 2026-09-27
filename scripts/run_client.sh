#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v love >/dev/null 2>&1; then
    echo "Erro: Love2D (love) nao encontrado no PATH."
    echo "Instale atraves de https://love2d.org ou via gerenciador de pacotes."
    exit 1
fi

echo "Starting Loci Arena Love2D client..."
exec love "$ROOT_DIR/client" "$@"
