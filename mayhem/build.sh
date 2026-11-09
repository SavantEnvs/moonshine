#!/usr/bin/env bash
#
# mayhem/build.sh — mining layer for the BinTokenizer blob-parser bug: builds the libFuzzer harness
# from mayhem/harnesses (also linked against the run-once standalone driver) and the dependency-free
# doctest suites that test.sh runs. The harness lives here because BASE predates core/reliability.
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
UTILS=("$CORE/moonshine-utils/string-utils.cpp" "$CORE/moonshine-utils/debug-utils.cpp")

# Leak detection off at build time (ASan/UBSan stay on); linked into every fuzz + standalone binary.
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/obj/lsan_off.o"
# The standalone driver is C; clang++ would mangle its LLVMFuzzerTestOneInput reference.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/obj/standalone_main.o"

# build_fuzzer <target> <harness> <extra link inputs...>
build_fuzzer() {
  local name="$1" harness="$2"; shift 2
  local common=(-std=c++20 -include cstring -D_GLIBCXX_ASSERTIONS "${INCS[@]}" "$SRC/mayhem/harnesses/$harness" "$@"
                "$OUT/obj/lsan_off.o")
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "${common[@]}" -o "$SRC/$name"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "${common[@]}" "$OUT/obj/standalone_main.o" \
    -o "$SRC/$name-standalone"
}

build_fuzzer fuzz_bin_tokenizer fuzz-bin-tokenizer.cpp \
  "$CORE/bin-tokenizer/bin-tokenizer.cpp" "${UTILS[@]}"

# Test suites: the model-free doctest binaries, with the project's normal flags (no sanitizers).
build_test() {
  local name="$1"; shift
  # shellcheck disable=SC2086
  $CXX -std=c++20 -include cstring -O1 $COVERAGE_FLAGS "${INCS[@]}" "$@" -o "$OUT/tests/$name"
}
build_test string-utils-test "$CORE/moonshine-utils/string-utils-test.cpp" "${UTILS[@]}"
build_test debug-utils-test "$CORE/moonshine-utils/debug-utils-test.cpp" "${UTILS[@]}"
build_test bin-tokenizer-test "$CORE/bin-tokenizer/bin-tokenizer-test.cpp" \
  "$CORE/bin-tokenizer/bin-tokenizer.cpp" "${UTILS[@]}"
build_test resampler-test "$CORE/resampler-test.cpp" "$CORE/resampler.cpp" "${UTILS[@]}"
