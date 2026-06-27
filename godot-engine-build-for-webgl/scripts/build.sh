#!/usr/bin/env bash
# Build Godot WASM engine for WeChat Mini Game
#
# Prerequisites:
#   - emsdk activated (emcc in PATH)
#   - scons installed
#   - patches already applied to the Godot repo
#   - custom.py configured with desired build options
#
# Usage:
#   ./build.sh [--clean]
#
#   Profile selection is done in ../custom.py (disable_3d, jolt, text_server, etc.)
#
#   Encryption (optional):
#     SCRIPT_AES256_ENCRYPTION_KEY=<64-hex-chars> ./build.sh
#
# Output:
#   engine/godot.wasm.br — brotli-compressed WASM
#   engine/godot.js      — post-processed Emscripten glue

set -euo pipefail

CLEAN="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Source local .env for toolchain paths (optional; see .env.example)
# ---------------------------------------------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
	source "$SCRIPT_DIR/.env"
fi

[ -n "${ELAN_PATH:-}" ] && export PATH="$ELAN_PATH:$PATH"
[ -n "${EMSDK_ENV:-}" ] && source "$EMSDK_ENV"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
if [ "$CLEAN" = "--clean" ]; then
	echo "==> Cleaning: removing bin/ and engine/"
	rm -rf "$GODOT_DIR/bin/"
fi

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
command -v emcc >/dev/null 2>&1 || {
	echo "ERROR: emcc not found. Activate emsdk first."
	exit 1
}
command -v scons >/dev/null 2>&1 || {
	echo "ERROR: scons not found."
	exit 1
}

SCONS="scons"
type scons &>/dev/null || SCONS="python3 -m SCons"

# ---------------------------------------------------------------------------
# Encryption key
# ---------------------------------------------------------------------------
KEY="${SCRIPT_AES256_ENCRYPTION_KEY:-0000000000000000000000000000000000000000000000000000000000000000}"

if [ "${#KEY}" -ne 64 ]; then
	echo "ERROR: SCRIPT_AES256_ENCRYPTION_KEY must be exactly 64 hex characters (got ${#KEY})" >&2
	exit 1
fi

if [ "$KEY" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then
	echo "==> Encryption: none (default key)"
else
	echo "==> Encryption: ${KEY:0:8}..."
fi

export SCRIPT_AES256_ENCRYPTION_KEY="$KEY"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "======================================"
echo " Building Godot WASM for WeChat MG"
echo " target   = template_release"
echo " config   = custom.py"
echo "======================================"
echo "==> Compiling..."

cd "$GODOT_DIR"

if [ ! -f "$GODOT_DIR/custom.py" ]; then
	if [ -f "$GODOT_DIR/custom.py.example" ]; then
		echo "==> custom.py not found, copying from custom.py.example"
		cp "$GODOT_DIR/custom.py.example" "$GODOT_DIR/custom.py"
	else
		echo "ERROR: custom.py not found and custom.py.example does not exist." >&2
		exit 1
	fi
fi

$SCONS \
	custom=./custom.py \
	target=template_release \
	-j"$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"

# ---------------------------------------------------------------------------
# Extract and post-process
# ---------------------------------------------------------------------------

if [ ! -f ./bin/.web_zip/godot.wasm ]; then
	echo "Missing ./bin/.web_zip/godot.wasm" >&2
	exit 1
fi

rm -f ./bin/.web_zip/godot.wasm.br
brotli ./bin/.web_zip/godot.wasm

echo ""
echo "Done. Outputs in ${GODOT_DIR}/bin/.web_zip/:"
ls -lh "${GODOT_DIR}/bin/.web_zip/"
