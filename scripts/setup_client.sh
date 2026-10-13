#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK_ONLY=false
if [ "$1" = "--check" ] || [ "$1" = "-c" ]; then
    CHECK_ONLY=true
fi

echo "=== Loci Arena - Client Setup (Love2D & Lua) ==="

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

# 1. Verifica se ja estao instalados
MISSING_LOVE=false
MISSING_LUA=false

if has_love; then
    LOVE_VER="$(love --version 2>&1 | head -n 1 || echo "love")"
    echo "[OK] Love2D encontrado: $LOVE_VER"
else
    MISSING_LOVE=true
fi

if has_lua; then
    LUA_BIN="$(command -v lua || command -v lua5.1 || command -v luajit || command -v lua5.4 || command -v lua5.3)"
    LUA_VER="$("$LUA_BIN" -v 2>&1 | head -n 1 || echo "lua")"
    echo "[OK] Lua encontrado: $LUA_VER ($LUA_BIN)"
else
    MISSING_LUA=true
fi

if [ "$MISSING_LOVE" = false ] && [ "$MISSING_LUA" = false ]; then
    echo "[OK] Todas as dependencias do cliente ja estao instaladas!"
    exit 0
fi

echo "-> Dependencias ausentes:"
[ "$MISSING_LOVE" = true ] && echo "   - Love2D (love)"
[ "$MISSING_LUA" = true ] && echo "   - Lua (lua / lua5.1)"

if [ "$CHECK_ONLY" = true ]; then
    echo "Modo de verificacao (--check): dependencias ausentes encontradas."
    exit 1
fi

# Configuracao de sudo se necessario
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Aviso: sudo nao encontrado e o script nao esta rodando como root."
    fi
fi

OS_TYPE="$(uname -s 2>/dev/null || echo "Linux")"

install_debian_ubuntu() {
    echo "-> Gerenciador detectado: apt-get (Debian / Ubuntu)"
    PKGS=()
    if [ "$MISSING_LOVE" = true ]; then
        PKGS+=("love")
    fi
    if [ "$MISSING_LUA" = true ]; then
        if apt-cache show lua5.1 >/dev/null 2>&1; then
            PKGS+=("lua5.1")
        elif apt-cache show lua >/dev/null 2>&1; then
            PKGS+=("lua")
        elif apt-cache show lua5.4 >/dev/null 2>&1; then
            PKGS+=("lua5.4")
        else
            PKGS+=("lua5.3")
        fi
    fi

    echo "-> Atualizando repositorios e instalando: ${PKGS[*]}..."
    $SUDO apt-get update
    $SUDO apt-get install -y "${PKGS[@]}"
}

install_arch() {
    echo "-> Gerenciador detectado: pacman (Arch Linux)"
    PKGS=()
    [ "$MISSING_LOVE" = true ] && PKGS+=("love")
    [ "$MISSING_LUA" = true ] && PKGS+=("lua")
    echo "-> Instalando pacotes via pacman: ${PKGS[*]}..."
    $SUDO pacman -Sy --noconfirm "${PKGS[@]}"
}

install_fedora() {
    echo "-> Gerenciador detectado: dnf (Fedora / RHEL)"
    PKGS=()
    [ "$MISSING_LOVE" = true ] && PKGS+=("love")
    [ "$MISSING_LUA" = true ] && PKGS+=("lua")
    echo "-> Instalando pacotes via dnf: ${PKGS[*]}..."
    $SUDO dnf install -y "${PKGS[@]}"
}

install_opensuse() {
    echo "-> Gerenciador detectado: zypper (openSUSE)"
    PKGS=()
    [ "$MISSING_LOVE" = true ] && PKGS+=("love")
    [ "$MISSING_LUA" = true ] && PKGS+=("lua")
    echo "-> Instalando pacotes via zypper: ${PKGS[*]}..."
    $SUDO zypper install -y "${PKGS[@]}"
}

install_macos() {
    echo "-> Sistema detectado: macOS"
    if command -v brew >/dev/null 2>&1; then
        echo "-> Instalando dependencias via Homebrew..."
        if [ "$MISSING_LUA" = true ]; then
            brew install lua
        fi
        if [ "$MISSING_LOVE" = true ]; then
            brew install love || brew install --cask love
        fi
    else
        echo "Erro: Homebrew nao encontrado."
        echo "Instale o Homebrew em https://brew.sh ou baixe o Love2D em https://love2d.org"
        exit 1
    fi
}

install_windows() {
    echo "-> Ambiente Windows/MSYS detectado."
    if command -v winget >/dev/null 2>&1; then
        echo "-> Tentando instalacao via winget..."
        [ "$MISSING_LOVE" = true ] && winget install --id Love2D.Love -e --accept-source-agreements --accept-package-agreements || true
        [ "$MISSING_LUA" = true ] && winget install --id Lua.Lua -e --accept-source-agreements --accept-package-agreements || true
    elif command -v choco >/dev/null 2>&1; then
        echo "-> Tentando instalacao via Chocolatey..."
        [ "$MISSING_LOVE" = true ] && choco install love-release -y
        [ "$MISSING_LUA" = true ] && choco install lua -y
    elif command -v scoop >/dev/null 2>&1; then
        echo "-> Tentando instalacao via Scoop..."
        [ "$MISSING_LOVE" = true ] && scoop install love
        [ "$MISSING_LUA" = true ] && scoop install lua
    else
        echo "Nenhum gerenciador de pacotes compativel (winget, choco, scoop) encontrado no Windows."
        echo "Baixe manualmente:"
        echo "  - Love2D: https://love2d.org"
        echo "  - Lua: https://www.lua.org/download.html"
        exit 1
    fi
}

case "$OS_TYPE" in
    [Ll]inux*)
        if command -v apt-get >/dev/null 2>&1; then
            install_debian_ubuntu
        elif command -v pacman >/dev/null 2>&1; then
            install_arch
        elif command -v dnf >/dev/null 2>&1; then
            install_fedora
        elif command -v zypper >/dev/null 2>&1; then
            install_opensuse
        else
            echo "Erro: Gerenciador de pacotes Linux nao suportado automaticamente."
            echo "Instale Love2D e Lua manualmente com o gerenciador da sua distribuicao."
            exit 1
        fi
        ;;
    [Dd]arwin*)
        install_macos
        ;;
    [Mm][Ss][Yy][Ss]*|[Mm][Ii][Nn][Gg][Ww]*|[Cc][Yy][Gg][Ww][Ii][Nn]*)
        install_windows
        ;;
    *)
        echo "Sistema operacional nao suportado automaticamente: $OS_TYPE"
        exit 1
        ;;
esac

# Verificacao pos-instalacao
if has_love && has_lua; then
    echo "[OK] Love2D e Lua configurados com sucesso!"
    exit 0
else
    echo ""
    echo "Aviso: A instalacao automatica foi executada, mas uma ou mais ferramentas ainda nao foram encontradas no PATH."
    if ! has_love; then
        echo " - Love2D: certifique-se de que o executavel 'love' esta no seu PATH (https://love2d.org)"
    fi
    if ! has_lua; then
        echo " - Lua: certifique-se de que o executavel 'lua' esta no seu PATH (https://www.lua.org)"
    fi
    exit 1
fi
