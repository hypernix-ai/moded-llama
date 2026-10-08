#!/usr/bin/env bash
# Rebuild this repository's llama.cpp tree from HyperNix-pip's native/ggml-hnx.
#
#   hypernix/sync-source.sh /path/to/HyperNix-pip
#
# 1. reads the llama.cpp revision HyperNix-pip pins (LLAMA_REF in its build.sh)
# 2. clones that revision fresh and runs HyperNix-pip's own patcher on it
# 3. checks the decoder against the Python encoder (before anything is
#    overwritten, so a failing decoder never reaches this repository)
# 4. replaces the tree at the repository root with the result
#
# Always from a pristine clone, never by re-patching what is already here:
# the patcher skips a tree it believes is patched, so a change to the patcher
# or to a decoder would otherwise never land.
#
# Left alone: .git, .github, hypernix, bin, README.md. The upstream README is
# kept as README.upstream.md, and .gitignore gets the lines that let bin/ be
# committed. The result is recorded in .hypernix-sync.json.
#
# Environment: LLAMA_REPO (default the upstream GitHub URL), LLAMA_REF
# (default: whatever HyperNix-pip pins).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HP="${1:?usage: sync-source.sh /path/to/HyperNix-pip}"
HP="$(cd "$HP" && pwd)"
NATIVE_PATH="${NATIVE_PATH:-native/ggml-hnx}"
NATIVE="$HP/$NATIVE_PATH"
LLAMA_REPO="${LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"

[ -f "$NATIVE/build.sh" ] || { echo "sync-source.sh: $NATIVE/build.sh not found" >&2; exit 1; }
[ -f "$NATIVE/tools/patch_llamacpp.py" ] || { echo "sync-source.sh: patcher not found in $NATIVE/tools" >&2; exit 1; }

if [ -z "${LLAMA_REF:-}" ]; then
  # LLAMA_REF="${LLAMA_REF:-b10883}"  ->  b10883
  # shellcheck disable=SC2016  # the single quotes are the point: a literal ${ in the pattern
  LLAMA_REF="$(sed -n 's/^LLAMA_REF="\${LLAMA_REF:-\([^}]*\)}".*/\1/p' "$NATIVE/build.sh" | head -n1)"
fi
[ -n "$LLAMA_REF" ] || { echo "sync-source.sh: could not read LLAMA_REF from $NATIVE/build.sh" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "==> llama.cpp $LLAMA_REF"
git clone -q --depth 1 --branch "$LLAMA_REF" "$LLAMA_REPO" "$work/llama.cpp"

echo "==> registering the HyperNix types"
python3 "$NATIVE/tools/patch_llamacpp.py" "$work/llama.cpp"

echo "==> checking the decoder against the Python encoder"
cmake -S "$NATIVE" -B "$work/selftest" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$work/selftest" --target hnx_selftest -j"$(nproc 2>/dev/null || echo 4)" >/dev/null
if PYTHONPATH="$HP/src" python3 -c "import hypernix.quant.subbit" 2>/dev/null; then
  PYTHONPATH="$HP/src" python3 "$NATIVE/tools/gen_vectors.py" "$work/selftest/vectors.bin"
  "$work/selftest/hnx_selftest" "$work/selftest/vectors.bin"
else
  echo "    hypernix is not importable (needs numpy); running the self-contained checks only."
  "$work/selftest/hnx_selftest"
fi

native_tree="$(git -C "$HP" rev-parse "HEAD:$NATIVE_PATH")"
hp_commit="$(git -C "$HP" rev-parse HEAD)"

echo "==> replacing the tree"
# Everything at the top level except what belongs to this repository, and
# except the HyperNix-pip checkout itself when it sits inside it (CI checks
# it out to ./hp).
keep=(! -name .git ! -name .github ! -name hypernix ! -name bin ! -name README.md)
if [ "$(dirname "$HP")" = "$ROOT" ]; then keep+=(! -name "$(basename "$HP")"); fi
find "$ROOT" -mindepth 1 -maxdepth 1 "${keep[@]}" -exec rm -rf {} +

(cd "$work/llama.cpp" && tar --exclude=./.git --exclude=./.github --exclude=./README.md -cf - .) \
  | (cd "$ROOT" && tar xf -)

mv "$work/llama.cpp/README.md" "$ROOT/README.upstream.md" 2>/dev/null || cp "$work/llama.cpp/README.md" "$ROOT/README.upstream.md"
cat >> "$ROOT/.gitignore" <<'EOF'

# moded-llama: keep the compiled build
!/bin/
!/bin/**
EOF

cat > "$ROOT/.hypernix-sync.json" <<EOF
{
  "llama_ref": "$LLAMA_REF",
  "hypernix_repo": "${HYPERNIX_REPO:-trail-b1az3r/HyperNix-pip}",
  "hypernix_commit": "$hp_commit",
  "native_path": "$NATIVE_PATH",
  "native_tree": "$native_tree"
}
EOF
echo "==> done: llama.cpp $LLAMA_REF + $NATIVE_PATH @ ${native_tree:0:12}"
