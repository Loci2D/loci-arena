#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if command -v lua5.1 >/dev/null 2>&1; then
    LUA_BIN="lua5.1"
elif command -v lua >/dev/null 2>&1; then
    LUA_BIN="lua"
else
    echo "[ERROR] Lua interpreter (lua5.1 or lua) not found." >&2
    exit 1
fi

UNIT_ONLY=false
if [ "${1:-}" = "--unit" ]; then
    UNIT_ONLY=true
fi

UNIT_SUITES=(
    "tests/test_combat_system.lua"
    "tests/test_character_and_respawn.lua"
    "tests/test_skills_and_combat_flow.lua"
    "tests/test_movement_sync.lua"
    "tests/test_client_modules.lua"
)

SDK_SUITES=(
    "tests/test_integration.lua"
    "scripts/test_wall_collision.lua"
)

SUITES=("${UNIT_SUITES[@]}")
if [ "$UNIT_ONLY" = false ]; then
    if [ ! -f "$ROOT_DIR/client/loci2d/loci_client.lua" ]; then
        echo "[ERROR] client/loci2d SDK not found. Run ./scripts/setup_sdk.sh --download (or pass --unit)." >&2
        exit 1
    fi
    SUITES+=("${SDK_SUITES[@]}")
fi

echo "=== Loci Arena Test Runner ($LUA_BIN) ==="

passed=0
failed=0
failed_suites=()

for suite in "${SUITES[@]}"; do
    echo ""
    echo "--> Running $suite..."
    if "$LUA_BIN" "$suite"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failed_suites+=("$suite")
    fi
done

echo ""
echo "========================================"
echo "Suites passed: $passed / ${#SUITES[@]}"
if [ "$failed" -gt 0 ]; then
    echo "Failed suites:"
    for s in "${failed_suites[@]}"; do
        echo "  - $s"
    done
    exit 1
fi
echo "All test suites passed!"
