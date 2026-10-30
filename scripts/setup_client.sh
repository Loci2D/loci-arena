#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK_ONLY=false
if [ "$1" = "--check" ] || [ "$1" = "-c" ]; then
    CHECK_ONLY=true
fi

echo "=== Loci Arena - Client Setup (Love2D & Lua) ==="

# 0. Configura o SDK do cliente (symlink local ou download de release)
if [ "$CHECK_ONLY" = false ]; then
    if [ ! -d "$ROOT_DIR/client/loci2d" ] || [ "$1" = "--download" ] || [ "$1" = "-d" ] || [ "$1" = "--force" ]; then
        "$ROOT_DIR/scripts/setup_sdk.sh" "$@"
    fi
fi

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

# 1. Verifica se ja estao instalados
MISSING_LOVE=false
MISSING_LUA=false
MISSING_PB=false

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

if has_protobuf; then
    echo "[OK] lua-protobuf (pb) encontrado no client."
else
    MISSING_PB=true
fi

if [ "$MISSING_LOVE" = false ] && [ "$MISSING_LUA" = false ] && [ "$MISSING_PB" = false ]; then
    echo "[OK] Todas as dependencias do cliente ja estao instaladas!"
    exit 0
fi

echo "-> Dependencias ausentes:"
[ "$MISSING_LOVE" = true ] && echo "   - Love2D (love)"
[ "$MISSING_LUA" = true ] && echo "   - Lua (lua / lua5.1)"
[ "$MISSING_PB" = true ] && echo "   - lua-protobuf (pb.so / pb.dylib)"

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
    if [ "$MISSING_LUA" = true ]; then
        if command -v brew >/dev/null 2>&1; then
            echo "-> Instalando Lua via Homebrew..."
            brew install lua
        else
            echo "Aviso: Homebrew nao encontrado para instalar Lua."
        fi
    fi

    if [ "$MISSING_LOVE" = true ]; then
        echo "-> Tentando instalar Love2D..."
        # Tenta via brew se disponivel (pode falhar se o cask estiver desabilitado pelo Gatekeeper)
        if command -v brew >/dev/null 2>&1; then
            brew install love 2>/dev/null || brew install --cask love 2>/dev/null || true
        fi

        # Fallback oficial via GitHub release caso o cask do Homebrew esteja desabilitado
        if ! has_love; then
            echo "-> Baixando Love2D 11.5 oficial para macOS..."
            LOVE_ZIP="/tmp/love-macos.zip"
            LOVE_TMP_DIR="/tmp/love-install"
            curl -fSL -o "$LOVE_ZIP" "https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip"
            mkdir -p "$LOVE_TMP_DIR"
            unzip -q -o "$LOVE_ZIP" -d "$LOVE_TMP_DIR"
            
            TARGET_APP="/Applications/love.app"
            if [ -w "/Applications" ]; then
                rm -rf "$TARGET_APP"
                mv "$LOVE_TMP_DIR/love.app" "$TARGET_APP"
            else
                TARGET_APP="$HOME/Applications/love.app"
                mkdir -p "$HOME/Applications"
                rm -rf "$TARGET_APP"
                mv "$LOVE_TMP_DIR/love.app" "$TARGET_APP"
            fi

            # Remove a quarentena do macOS (Gatekeeper) para permitir execucao
            if command -v xattr >/dev/null 2>&1; then
                xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
            fi

            # Cria link simbolico para o PATH
            BIN_DIR="/opt/homebrew/bin"
            [ ! -d "$BIN_DIR" ] && BIN_DIR="/usr/local/bin"
            if [ -w "$BIN_DIR" ]; then
                ln -sf "$TARGET_APP/Contents/MacOS/love" "$BIN_DIR/love"
            elif [ -n "$SUDO" ]; then
                $SUDO ln -sf "$TARGET_APP/Contents/MacOS/love" "$BIN_DIR/love"
            fi

            rm -rf "$LOVE_ZIP" "$LOVE_TMP_DIR"
        fi
    fi

    if [ "$MISSING_PB" = true ]; then
        echo "-> Compilando lua-protobuf (pb.so) para o client Love2D..."
        PB_TMP_DIR="/tmp/pb-build-$$"
        mkdir -p "$PB_TMP_DIR"
        mkdir -p "$ROOT_DIR/client/loci2d/lib"
        curl -fSL -o "$PB_TMP_DIR/pb.c" "https://raw.githubusercontent.com/starwing/lua-protobuf/master/pb.c" 2>/dev/null || true
        curl -fSL -o "$PB_TMP_DIR/pb.h" "https://raw.githubusercontent.com/starwing/lua-protobuf/master/pb.h" 2>/dev/null || true

        LOVE_LUA_INC="/Applications/love.app/Contents/Frameworks/Lua.framework/Versions/A/Headers"
        SDK_FLAG=""
        if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]; then
            SDK_FLAG="-isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
        elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
            SDK_FLAG="-isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
        fi

        if [ -f "$PB_TMP_DIR/pb.c" ] && [ -d "$LOVE_LUA_INC" ]; then
            clang -O2 -bundle -undefined dynamic_lookup $SDK_FLAG -I"$LOVE_LUA_INC" "$PB_TMP_DIR/pb.c" -o "$ROOT_DIR/client/loci2d/lib/pb.so" 2>/dev/null || true
        fi
        rm -rf "$PB_TMP_DIR"
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
if has_love && has_lua && has_protobuf; then
    echo "[OK] Love2D, Lua e lua-protobuf configurados com sucesso!"
    exit 0
else
    echo ""
    echo "Aviso: A instalacao automatica foi executada, mas uma ou mais dependencias ainda estao pendentes."
    if ! has_love; then
        echo " - Love2D: certifique-se de que o executavel 'love' esta no seu PATH (https://love2d.org)"
    fi
    if ! has_lua; then
        echo " - Lua: certifique-se de que o executavel 'lua' esta no seu PATH (https://www.lua.org)"
    fi
    if ! has_protobuf; then
        echo " - lua-protobuf: biblioteca 'pb.so' ausente em client/loci2d/lib/"
    fi
    exit 1
fi
