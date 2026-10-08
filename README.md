# moded-llama

[llama.cpp](https://github.com/ggml-org/llama.cpp) patched by
[HyperNix-pip](https://github.com/trail-b1az3r/hypernix-pip)'s `ggml-hnx`
so it can load HyperNix models, **with the compiled build included**.

- **Upstream:** `ggml-org/llama.cpp` at tag `b10883` (the revision `native/ggml-hnx/build.sh` pins).
- **Added:** every GGML type HyperNix writes (ids 200-211: the sub-bit tiers
  `IQ0.9_L`, `IQ0.75_M`, `IQ0.5_XXXL`, `IQ0.25_UXL`, `INT1`, `HNX_1375BIT`, and
  the `INT8`, `INT4`, `INT3`, `INT2`, `FP2`, `FP8` codebooks), plus a `Q8_K`
  weight kernel upstream lacks. Details: `native/ggml-hnx/README.md` in HyperNix-pip.
- **Where the patch is:** `ggml/include/ggml.h`, `ggml/src/CMakeLists.txt`,
  `ggml/src/ggml.c`, `ggml/src/ggml-cpu/ggml-cpu.c`, and the new files
  `ggml/src/ggml-hnx.{c,h}` and `ggml/src/ggml-hnx-shim.{c,h}`.

## Compiled build

`bin/linux-x86_64/` holds the Release build (`llama-cli`, `llama-server`,
`llama-quantize`, `llama-bench`, ... and the shared libraries they need).

```bash
bin/linux-x86_64/llama-cli -m your-model.gguf -p "hello"
bin/linux-x86_64/llama-server -m your-model.gguf
```

- Linux x86_64, GCC 13.3, CPU backend only. `GGML_NATIVE=OFF`, so it does
  not assume the build machine's CPU.
- Binaries use an `$ORIGIN` runpath: keep each executable next to its `lib*.so`
  files and the directory can be moved anywhere.
- The HyperNix types run on the CPU backend. For CUDA/ROCm, rebuild (below).
- The decoder was checked against HyperNix's Python encoder (99 test vectors,
  exact match) before this was built.
- `llama-quantize` deliberately refuses to *write* the HyperNix types (use `hnx quantize`).

## Rebuild

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF \
  -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_FLAGS="-include cstdint" -DCMAKE_C_FLAGS="-include stdint.h"
cmake --build build -j
```

Add `-DGGML_CUDA=ON` or `-DGGML_HIPBLAS=ON` for a GPU backend.

## License

llama.cpp is MIT licensed; its `LICENSE` is at the repository root,
unmodified (Copyright (c) 2023-2026 The ggml authors). Third-party notices are
in `licenses/`.

The `ggml-hnx` files (`ggml/src/ggml-hnx*.{c,h}`) and the HyperNix edits to the
four patched upstream files come from HyperNix-pip and remain under
HyperNix-pip's own license (see its `LICENSE`).

The upstream README is kept as `README.upstream.md`.
