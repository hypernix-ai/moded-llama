#!/usr/bin/env bash
# Check a finished build and pack it into a release tarball.
#
#   hypernix/package.sh <variant> <asset-name> <out-dir>
#
# Reads BUILD_DIR (default build-<variant>). Writes <out-dir>/<asset-name>.tar.gz
# holding bin/ (executables and the shared libraries beside them), LICENSE,
# licenses/ and BUILD_INFO.txt.
#
# The checks are what can be checked without a GPU: that the HyperNix types
# are really compiled in, that a CUDA build really has its CUDA library, and
# that a CPU build starts.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

VARIANT="${1:?usage: package.sh <variant> <asset-name> <out-dir>}"
ASSET="${2:?asset name}"
OUT="${3:?out dir}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-$VARIANT}"
BIN="$BUILD_DIR/bin"

fail() { echo "package.sh: $*" >&2; exit 1; }

[ -d "$BIN" ] || fail "$BIN does not exist; run hypernix/build.sh $VARIANT first"

# 1. the HyperNix types are in the library that holds ggml's type table
# shellcheck disable=SC2012  # a glob for the one versioned library; names are ours
base="$(ls "$BIN"/libggml-base.so.*.* 2>/dev/null | head -n1)"
[ -n "$base" ] || fail "no libggml-base in $BIN"
for name in IQ0.5_XXXL INT1 HNX_1375BIT; do
  # No -q: grep must read all of strings' output, or pipefail reports the
  # SIGPIPE that strings gets when grep quits early as a failure.
  strings "$base" | grep -Fx -- "$name" >/dev/null || fail "$name is not in $(basename "$base"); the patch did not make it into this build"
done

# 2. a GPU variant has its backend library
case "$VARIANT" in
  cuda)   ls "$BIN"/libggml-cuda.so* >/dev/null 2>&1 || fail "cuda variant but no libggml-cuda in $BIN" ;;
  rocm)   ls "$BIN"/libggml-hip.so*  >/dev/null 2>&1 || fail "rocm variant but no libggml-hip in $BIN" ;;
  vulkan) ls "$BIN"/libggml-vulkan.so* >/dev/null 2>&1 || fail "vulkan variant but no libggml-vulkan in $BIN" ;;
esac

# 3. a CPU build runs. A GPU build is linked against the driver
# (libcuda.so.1 and friends), which a CI container does not have, so it
# cannot be started there and is not.
if [ "$VARIANT" = "cpu" ]; then
  "$BIN/llama-cli" --version >/dev/null 2>&1 || fail "llama-cli --version failed"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkg="$stage/$ASSET"
mkdir -p "$pkg" "$OUT"
cp -a "$BIN" "$pkg/bin"
cp "$ROOT/LICENSE" "$pkg/LICENSE"
cp -a "$ROOT/licenses" "$pkg/licenses"

{
  echo "variant:        $VARIANT"
  echo "asset:          $ASSET"
  echo "llama.cpp:      $(jq -r .llama_ref "$ROOT/.hypernix-sync.json" 2>/dev/null || echo unknown)"
  echo "hypernix-pip:   $(jq -r .hypernix_commit "$ROOT/.hypernix-sync.json" 2>/dev/null || echo unknown)"
  echo "native tree:    $(jq -r .native_tree "$ROOT/.hypernix-sync.json" 2>/dev/null || echo unknown)"
  echo "moded-llama:    $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "compiler:       $(c++ --version 2>/dev/null | head -n1 || echo unknown)"
  if command -v nvcc >/dev/null 2>&1; then echo "nvcc:           $(nvcc --version | tail -n1)"; fi
  echo "cmake args:"
  # shellcheck source=variants.sh
  . "$HERE/variants.sh"
  variant_cmake_args "$VARIANT" | sed 's/^/  /'
} > "$pkg/BUILD_INFO.txt"

tar -C "$stage" -czf "$OUT/$ASSET.tar.gz" "$ASSET"
echo "==> $OUT/$ASSET.tar.gz ($(du -h "$OUT/$ASSET.tar.gz" | cut -f1))"
