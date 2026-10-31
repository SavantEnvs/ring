#!/usr/bin/env bash
# Builds the Ring fuzz harnesses (sanitized, plus standalone reproducers) and a normal-flags
# `ring` interpreter that mayhem/test.sh uses as its functional oracle.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
LANG_SRC="$SRC/language/src"
INC="-I$SRC/language/include"
OUT="$SRC/mayhem/out"
rm -rf "$OUT"
mkdir -p "$OUT/fuzz" "$OUT/normal"

# Every library source; ring.c / ringw.c hold the CLI main().
mapfile -t LIBSRC < <(cd "$LANG_SRC" && ls *.c | grep -v '^ring\(w\)\?\.c$')

# 1) Sanitized library, instrumented for coverage (fuzzer-no-link) so the fuzzed code is visible.
printf '%s\n' "${LIBSRC[@]}" | xargs -P "$MAYHEM_JOBS" -I{} \
  $CC -O1 -w $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $INC \
      -c "$LANG_SRC/{}" -o "$OUT/fuzz/{}.o"
ar rcs "$OUT/fuzz/libring.a" "$OUT"/fuzz/*.o

# 2) Harnesses: libFuzzer binary + standalone reproducer, each with LSan switched off.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OUT/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/standalone_main.o"
for t in fuzz_ring_compile fuzz_ring_objfile; do
  $CC -O1 -w $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $INC -c "mayhem/$t.c" -o "$OUT/fuzz/$t.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OUT/fuzz/$t.o" "$OUT/lsan_off.o" \
      "$OUT/fuzz/libring.a" -lm -ldl -lpthread -o "$SRC/$t"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/standalone_main.o" "$OUT/fuzz/$t.o" "$OUT/lsan_off.o" \
      "$OUT/fuzz/libring.a" -lm -ldl -lpthread -o "$SRC/$t-standalone"
done

# 3) Test oracle: the interpreter with the project's normal flags, separate from the sanitized build.
printf '%s\n' "${LIBSRC[@]}" | xargs -P "$MAYHEM_JOBS" -I{} \
  $CC -O2 -w $COVERAGE_FLAGS $INC -c "$LANG_SRC/{}" -o "$OUT/normal/{}.o"
$CC -O2 -w $COVERAGE_FLAGS $INC "$LANG_SRC/ring.c" "$OUT"/normal/*.o -lm -ldl -lpthread $COVERAGE_FLAGS \
    -o "$OUT/normal/ring"
# Ring resolves `load` and `loadsyntax` against the interpreter's own folder and its sibling
# libraries/, so give the test interpreter the stock layout.
ln -sfn "$SRC/bin/load" "$OUT/normal/load"
ln -sfn "$SRC/libraries" "$OUT/libraries"
ln -sfn "$SRC/lib" "$OUT/lib"
