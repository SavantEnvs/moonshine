#!/usr/bin/env bash
#
# mayhem/build.sh — builds the five libFuzzer harnesses from core/reliability (each also linked
# against the run-once standalone driver) and the dependency-free doctest suites that test.sh runs.
# Runs inside the commit image as `mayhem` in /mayhem; re-runnable and network-free.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
CORE="$SRC/core"
OUT="$SRC/build"
mkdir -p "$OUT/tests" "$OUT/obj"

INCS=(-I"$CORE" -I"$CORE/moonshine-utils" -I"$CORE/bin-tokenizer" -I"$CORE/ort-utils"
      -I"$CORE/cpp-annote/src" -I"$CORE/third-party/onnxruntime/include"
      -I"$CORE/third-party/doctest")
UTILS=("$CORE/moonshine-utils/string-utils.cpp" "$CORE/moonshine-utils/debug-utils.cpp"
       "$CORE/moonshine-utils/file-utils.cpp" "$CORE/moonshine-utils/file-information.cpp")
ORT_UTILS=("$CORE/ort-utils/ort-utils.cpp" "$CORE/ort-utils/ort-utils-ep.cpp"
           "$CORE/ort-utils/moonshine-ort-allocator.cpp" "$CORE/ort-utils/moonshine-tensor-view.cpp"
           "$CORE/ort-utils/moonshine-tensor.cpp")
case "$(uname -m)" in
  aarch64|arm64) ORT_DIR="$CORE/third-party/onnxruntime/lib/linux/aarch64" ;;
  *)             ORT_DIR="$CORE/third-party/onnxruntime/lib/linux/x86_64" ;;
esac
ORT_LIB="$ORT_DIR/libonnxruntime.so.1"

# Leak detection off at build time (ASan/UBSan stay on); linked into every fuzz + standalone binary.
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/obj/lsan_off.o"
# The standalone driver is C; clang++ would mangle its LLVMFuzzerTestOneInput reference.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/obj/standalone_main.o"

# build_fuzzer <target> <harness> <extra link inputs...>
build_fuzzer() {
  local name="$1" harness="$2"; shift 2
  local common=(-std=c++20 -D_GLIBCXX_ASSERTIONS "${INCS[@]}" "$CORE/reliability/$harness" "$@"
                "$OUT/obj/lsan_off.o")
  local rpath=()
  [ "$name" != fuzz_tensor_view ] || rpath=(-Wl,-rpath,"$ORT_DIR")
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "${common[@]}" "${rpath[@]}" -o "$SRC/$name"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "${common[@]}" "$OUT/obj/standalone_main.o" "${rpath[@]}" \
    -o "$SRC/$name-standalone"
}

build_fuzzer fuzz_bin_tokenizer fuzz-bin-tokenizer.cpp \
  "$CORE/bin-tokenizer/bin-tokenizer.cpp" "${UTILS[@]}"
build_fuzzer fuzz_wav_pcm fuzz-wav-pcm.cpp "${UTILS[@]}"
build_fuzzer fuzz_resampler fuzz-resampler.cpp "$CORE/resampler.cpp" "${UTILS[@]}"
build_fuzzer fuzz_string_utils fuzz-string-utils.cpp "$CORE/moonshine-utils/string-utils.cpp"
build_fuzzer fuzz_tensor_view fuzz-tensor-view.cpp "${ORT_UTILS[@]}" "${UTILS[@]}" "$ORT_LIB"

# Test suites: the model-free doctest binaries, with the project's normal flags (no sanitizers).
build_test() {
  local name="$1"; shift
  # shellcheck disable=SC2086
  $CXX -std=c++20 -O1 $COVERAGE_FLAGS "${INCS[@]}" "$@" -o "$OUT/tests/$name"
}
build_test string-utils-test "$CORE/moonshine-utils/string-utils-test.cpp" "${UTILS[@]}"
build_test debug-utils-test "$CORE/moonshine-utils/debug-utils-test.cpp" "${UTILS[@]}"
build_test file-utils-test "$CORE/moonshine-utils/file-utils-test.cpp" "${UTILS[@]}"
build_test file-information-test "$CORE/moonshine-utils/file-information-test.cpp" "${UTILS[@]}"
build_test bin-tokenizer-test "$CORE/bin-tokenizer/bin-tokenizer-test.cpp" \
  "$CORE/bin-tokenizer/bin-tokenizer.cpp" "${UTILS[@]}"
build_test resampler-test "$CORE/resampler-test.cpp" "$CORE/resampler.cpp" "${UTILS[@]}"
