#!/usr/bin/env bash
# Compile this tree.
#
#   hypernix/build.sh                  CPU build            -> build-cpu/bin
#   hypernix/build.sh cuda             NVIDIA GPUs          -> build-cuda/bin
#   hypernix/build.sh rocm             AMD GPUs             -> build-rocm/bin
#   hypernix/build.sh vulkan           Vulkan               -> build-vulkan/bin
#   hypernix/build.sh cuda -DFOO=bar   anything after the variant goes to CMake
#   hypernix/build.sh --print cuda     show the exact commands, run nothing
#
# Environment: BUILD_DIR (default build-<variant>), JOBS (default: all cores),
# CUDA_ARCHS and GPU_TARGETS (see hypernix/variants.sh).
#
# The build directory also gets compile_commands.json, for clangd and friends.
#
# The HyperNix GGML types run on llama.cpp's CPU backend in every variant; a
# GPU variant puts the rest of the graph on the GPU (see README.md).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=variants.sh
. "$HERE/variants.sh"

PRINT_ONLY=0
if [ "${1:-}" = "--print" ]; then
  PRINT_ONLY=1
  shift
fi
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

VARIANT="${1:-cpu}"
[ "$#" -gt 0 ] && shift
case " $(variant_names) " in
  *" $VARIANT "*) ;;
  *) echo "build.sh: unknown variant '$VARIANT' (one of: $(variant_names))" >&2; exit 2 ;;
esac
BUILD_DIR="${BUILD_DIR:-$ROOT/build-$VARIANT}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

ARGS=()
while IFS= read -r line; do ARGS+=("$line"); done < <(variant_cmake_args "$VARIANT")
ARGS+=("$@")

if [ "$PRINT_ONLY" = "1" ]; then
  printf 'cmake -S %q -B %q' "$ROOT" "$BUILD_DIR"
  printf ' %q' "${ARGS[@]}"
  printf '\ncmake --build %q -j%q\n' "$BUILD_DIR" "$JOBS"
  exit 0
fi

echo "==> configuring $VARIANT -> $BUILD_DIR"
cmake -S "$ROOT" -B "$BUILD_DIR" "${ARGS[@]}"
echo "==> building"
cmake --build "$BUILD_DIR" -j"$JOBS"

echo
echo "==> done: $BUILD_DIR/bin"
echo "    try:  $BUILD_DIR/bin/llama-cli -m YOUR-MODEL.gguf -p \"hello\""
