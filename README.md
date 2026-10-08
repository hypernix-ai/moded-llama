# moded-llama

[llama.cpp](https://github.com/ggml-org/llama.cpp) patched with
[HyperNix-pip](https://github.com/trail-b1az3r/HyperNix-pip)'s
`native/ggml-hnx`, so it can load HyperNix models. Compiled builds are
published as [Releases](../../releases) and kept up to date automatically.

- **Upstream:** `ggml-org/llama.cpp`, at the revision HyperNix-pip pins
  (see `.hypernix-sync.json`).
- **Added:** every GGML type HyperNix writes (ids 200-211: the sub-bit tiers
  `IQ0.9_L`, `IQ0.75_M`, `IQ0.5_XXXL`, `IQ0.25_UXL`, `INT1`, `HNX_1375BIT`, and
  the `INT8`, `INT4`, `INT3`, `INT2`, `FP2`, `FP8` codebooks), plus a `Q8_K`
  weight kernel upstream lacks. Details: `native/ggml-hnx/README.md` in HyperNix-pip.
- **Where the patch is:** `ggml/include/ggml.h`, `ggml/src/CMakeLists.txt`,
  `ggml/src/ggml.c`, `ggml/src/ggml-cpu/ggml-cpu.c`, and the new files
  `ggml/src/ggml-hnx.{c,h}` and `ggml/src/ggml-hnx-shim.{c,h}`.

## Download a build

From the [latest release](../../releases/latest):

| file | for |
|---|---|
| `moded-llama-linux-x86_64-cpu.tar.gz` | any x86_64 Linux machine |
| `moded-llama-linux-x86_64-cuda12.tar.gz` | NVIDIA GPUs |

```bash
tar xzf moded-llama-linux-x86_64-cpu.tar.gz
moded-llama-linux-x86_64-cpu/bin/llama-cli -m your-model.gguf -p "hello"
moded-llama-linux-x86_64-cpu/bin/llama-server -m your-model.gguf
```

- Keep each executable next to its `lib*.so` files (they find each other
  through an `$ORIGIN` runpath); the folder can then live anywhere.
- **CUDA build:** needs the NVIDIA driver and the CUDA 12 runtime libraries
  (`libcudart`, `libcublas`) on the machine; neither is bundled. It targets
  upstream's default architecture list, which includes PTX for sm_61, so
  Pascal cards (HyperNix's floor) work and JIT-compile on first run.
- **The HyperNix types run on the CPU backend in every build,** the CUDA one
  included: their tensors are computed on the CPU and the rest of the graph
  goes to the GPU. The patch does not add a CUDA kernel for them.
- `llama-quantize` deliberately refuses to *write* the HyperNix types; use
  `hnx quantize` from HyperNix-pip.
- Each archive has a `BUILD_INFO.txt` with the exact flags, compiler and
  source revisions.
- `bin/linux-x86_64/` in this repository is a one-time CPU snapshot kept from
  when the repository was created. It is **not** refreshed; the releases are.

## Compile it yourself

`hypernix/build.sh` is the single entry point, and CI uses the same one:

```bash
hypernix/build.sh                 # CPU    -> build-cpu/bin
hypernix/build.sh cuda            # NVIDIA -> build-cuda/bin   (needs the CUDA toolkit)
hypernix/build.sh rocm            # AMD    -> build-rocm/bin   (needs ROCm/HIP)
hypernix/build.sh vulkan          # Vulkan -> build-vulkan/bin (needs the Vulkan SDK)

hypernix/build.sh --print cuda    # show the exact cmake commands, run nothing
hypernix/build.sh cuda -DFOO=bar  # anything after the variant goes to CMake

CUDA_ARCHS="61;75;86" hypernix/build.sh cuda   # only these GPU architectures (faster)
GPU_TARGETS="gfx1030;gfx1100" hypernix/build.sh rocm
```

`--print cpu` shows what that expands to:

```bash
cmake -S . -B build-cpu \
  -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF -DLLAMA_BUILD_TESTS=OFF \
  -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  '-DCMAKE_CXX_FLAGS=-include cstdint' '-DCMAKE_C_FLAGS=-include stdint.h' \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build-cpu -j"$(nproc)"
```

A GPU variant adds `-DGGML_CUDA=ON`, `-DGGML_HIP=ON` or `-DGGML_VULKAN=ON`.
Why each shared flag is there is written in `hypernix/variants.sh`.
Every build directory gets a `compile_commands.json` for clangd and similar tools.

## How it stays up to date

`.github/workflows/hypernix-build.yml` watches HyperNix-pip's
`native/ggml-hnx`. When that folder's contents change:

1. **sync** - the llama.cpp tree here is rebuilt from a fresh clone of the pinned
   upstream revision, patched with HyperNix-pip's own patcher, and checked against
   HyperNix's Python encoder first (`hypernix/sync-source.sh`). If the decoder
   disagrees with the encoder, nothing is committed. The result is committed.
2. **build** - that commit is compiled for CPU and CUDA.
3. **release** - both are published as the release `native-<12 characters of the
   folder's git tree hash>`.

It starts three ways: HyperNix-pip's `notify-moded-llama` workflow sends a
`repository_dispatch` the moment the folder changes on `main` (this needs the
`MODED_LLAMA_DISPATCH_TOKEN` secret there); otherwise a check every six hours finds
the change on its own; or run it by hand from the Actions tab (tick *force* to
rebuild an unchanged folder). Commits elsewhere in HyperNix-pip are ignored.

If HyperNix-pip moves its pinned llama.cpp revision, the next run replaces the whole
tree here with the new one.

## License

llama.cpp is MIT licensed; its `LICENSE` is at the repository root, unmodified
(Copyright (c) 2023-2026 The ggml authors). Third-party notices are in `licenses/`,
and every release archive carries both.

The `ggml-hnx` files (`ggml/src/ggml-hnx*.{c,h}`) and the HyperNix edits to the four
patched upstream files come from HyperNix-pip and remain under HyperNix-pip's own
license (see its `LICENSE`).

The upstream README is kept as `README.upstream.md`.
