#!/usr/bin/env bash
# Runs Ring's own regression suite (language/tests/tests.ring): each listed script is run with the
# interpreter that mayhem/build.sh built with normal flags, and its output is diffed against the
# golden file in language/tests/correct. Nothing is compiled here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
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

RING="$SRC/mayhem/out/normal/ring"
if [ ! -x "$RING" ]; then
  echo "missing $RING: mayhem/build.sh did not build the test interpreter" >&2
  emit_ctrf ring-script-tests 0 1 0
  exit 1
fi

TESTS="$SRC/language/tests"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Tests write scratch files next to their scripts, so run them from a copy.
cp -a "$TESTS" "$WORK/tests"
export PATH="$SRC/mayhem/out/normal:$PATH"

# test35 depends on locale/clock output that differs between hosts, so it is not part of the oracle.
SKIP_RE='^general/test35\.ring$'

passed=0; failed=0
cd "$WORK/tests/scripts"
grep -v ':Condition' ../tests.ring | grep -o ':Command = "ring [^"]*"' \
  | sed 's/^:Command = "ring //; s/"$//' > "$WORK/cmds"

while IFS= read -r cmd; do
  f="${cmd%% *}"
  [[ "$f" =~ $SKIP_RE ]] && continue
  inp=/dev/null
  case "$cmd" in *" < "*) inp="${cmd##* < }" ;; esac
  name="${f%.ring}"; name="${name//\//_}.txt"
  golden="../correct/$name"
  if [ ! -f "$golden" ]; then
    echo "FAIL (no golden file) $f"; failed=$((failed+1)); continue
  fi
  timeout 30 "$RING" "$f" < "$inp" 2>&1 | tr -d '\r' > "$WORK/out.txt"
  if diff -q <(tr -d '\r' < "$golden") "$WORK/out.txt" >/dev/null; then
    passed=$((passed+1))
  else
    echo "FAIL $f"; failed=$((failed+1))
  fi
done < "$WORK/cmds"

emit_ctrf ring-script-tests "$passed" "$failed" 0
