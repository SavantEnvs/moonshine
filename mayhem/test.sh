#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the upstream doctest suites that mayhem/build.sh built (never compiles).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TESTS="$SRC/build/tests"
SUITES=(string-utils-test debug-utils-test bin-tokenizer-test resampler-test)

# The doctest binaries read and write relative paths, so run them in a scratch directory that
# holds the audio assets the resampler and debug-utils tests load.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SRC/test-assets/two_cities.wav" "$SRC/test-assets/beckett.wav" "$WORK/"

passed=0 failed=0 skipped=0
for suite in "${SUITES[@]}"; do
  if [ ! -x "$TESTS/$suite" ]; then
    echo "missing test binary $TESTS/$suite — mayhem/build.sh must build it" >&2
    failed=$(( failed + 1 ))
    continue
  fi
  out="$(cd "$WORK" && "$TESTS/$suite" --no-colors 2>&1)"
  rc=$?
  echo "$out" | tail -n 4
  summary="$(echo "$out" | sed -n 's/^\[doctest\] test cases: *\([0-9]*\) | *\([0-9]*\) passed | *\([0-9]*\) failed | *\([0-9]*\) skipped.*/\1 \2 \3 \4/p' | tail -n 1)"
  if [ -z "$summary" ]; then
    echo "no doctest summary from $suite (exit $rc)" >&2
    failed=$(( failed + 1 ))
    continue
  fi
  read -r _ p f s <<<"$summary"
  passed=$(( passed + p )); failed=$(( failed + f )); skipped=$(( skipped + s ))
  [ "$rc" -eq 0 ] || [ "$f" -gt 0 ] || failed=$(( failed + 1 ))
done

emit_ctrf doctest "$passed" "$failed" "$skipped"
