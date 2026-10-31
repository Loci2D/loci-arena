#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

has_love() {
    command -v love >/dev/null 2>&1
}

has_lua() {
    command -v lua >/dev/null 2>&1 || \
    command -v lua5.1 >/dev/null 2>&1 || \
    command -v luajit >/dev/null 2>&1 || \
    command -v lua5.4 >/dev/null 2>&1 || \
    command -v lua5.3 >/dev/null 2>&1
}

has_protobuf() {
    [ -f "$ROOT_DIR/client/loci2d/lib/pb.so" ] || \
    [ -f "$ROOT_DIR/client/loci2d/lib/pb.dylib" ] || \
    [ -f "$ROOT_DIR/client/loci2d/lib/pb.dll" ]
}

if [ ! -d "$ROOT_DIR/client/loci2d" ] || ! has_love || ! has_lua || ! has_protobuf; then
    echo "Dependencias do cliente (Love2D, Lua e/ou SDK loci2d) nao encontradas."
    echo "Executando configuracao automatica via setup_client.sh..."
    "$ROOT_DIR/scripts/setup_client.sh"
fi

if ! has_love; then
    echo "Erro: Love2D (love) nao encontrado no PATH."
    echo "Instale atraves de https://love2d.org ou execute './scripts/setup_client.sh'."
    exit 1
fi

echo "Starting Loci Arena Love2D client..."
cd "$ROOT_DIR/client"
exec love . "$@"
