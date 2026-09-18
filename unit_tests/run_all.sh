#!/usr/bin/env bash
# Compiles and runs each unit_tests/*.sv separately, and prints a summary.
# Run from the repo root: ./unit_tests/run_all.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0
fail=0

for tb in unit_tests/test_*.sv; do
    name=$(basename "$tb" .sv)
    out="$TMP_DIR/$name.out"

    if ! iverilog -g2012 -o "$out" src/modules/*.sv src/CPU.sv "$tb" > "$TMP_DIR/$name.compile.log" 2>&1; then
        echo "ERROR (compile): $name"
        fail=$((fail+1))
        continue
    fi

    result=$(vvp "$out" 2>/dev/null | grep -E "^(PASS|FAIL)")

    if [[ "$result" == PASS* ]]; then
        echo "$result"
        pass=$((pass+1))
    else
        echo "${result:-"FAIL (no output): $name"}"
        fail=$((fail+1))
    fi
done

echo "----"
echo "Total: $((pass+fail))  PASS: $pass  FAIL: $fail"

[ "$fail" -eq 0 ]
