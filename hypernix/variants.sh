# shellcheck shell=bash
# The one place that says how each flavour of this build is configured.
# Sourced by hypernix/build.sh (what you run) and by .github/workflows/build.yml
# (what CI runs), so the commands in the README and the released binaries
# cannot drift apart.
#
# Every variant shares the flags below, which are the ones HyperNix-pip's
# native/ggml-hnx/build.sh uses, plus an $ORIGIN runpath so a build
# directory (or an unpacked release) can be moved anywhere:
#
#   GGML_NATIVE=OFF   runs on any CPU of the same architecture, not only
#                     the one that built it
#   C++17             the standard upstream targets; newer compilers default
#                     to one that warns on upstream code
#   -include cstdint  newer libstdc++ no longer pulls <cstdint> in behind
#                     other headers, and some upstream files rely on that

variant_names() { echo "cpu cuda rocm vulkan"; }

# Prints one CMake argument per line.
#
#   CUDA_ARCHS   cuda only. Unset, upstream's own list is used: PTX for
#                sm_50 through sm_80 (so a Pascal card, which is HyperNix's
#                floor, JIT-compiles on first run) plus real code for the
#                newer cards. Set it, e.g. "61;75;86", to compile only those.
#   GPU_TARGETS  rocm only, e.g. "gfx1030;gfx1100". Unset, upstream's list.
variant_cmake_args() {
  local variant="${1:?variant}"
  # shellcheck disable=SC2016  # $ORIGIN is meant literally, for the linker
  printf '%s\n' \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    '-DCMAKE_CXX_FLAGS=-include cstdint' \
    '-DCMAKE_C_FLAGS=-include stdint.h' \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  case "$variant" in
    cpu) ;;
    cuda)
      echo "-DGGML_CUDA=ON"
      # libggml-cuda calls the CUDA *driver* API (cuMemCreate, ...), which
      # lives in libcuda.so.1 from the NVIDIA driver. A build container has
      # no driver, only a stub, so linking an executable against it fails
      # with "undefined reference to cuGetErrorString". The loader finds the
      # real libcuda at run time. Upstream's .devops/cuda.Dockerfile passes
      # the same flag for the same reason.
      echo "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined"
      if [ -n "${CUDA_ARCHS:-}" ]; then echo "-DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHS}"; fi
      ;;
    rocm)
      echo "-DGGML_HIP=ON"
      if [ -n "${GPU_TARGETS:-}" ]; then echo "-DGPU_TARGETS=${GPU_TARGETS}"; fi
      ;;
    vulkan) echo "-DGGML_VULKAN=ON" ;;
    *)
      echo "unknown variant '$variant' (one of: $(variant_names))" >&2
      return 1
      ;;
  esac
}
