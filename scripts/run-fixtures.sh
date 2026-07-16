#!/usr/bin/env bash
# Run golden CLI fixtures under .github/fixtures/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${NIXUP_BIN:-$ROOT/target/debug/nixup}"
FIXTURES="$ROOT/.github/fixtures"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN (build with cargo build -p nixup)" >&2
  exit 1
fi

failed=0
for dir in "$FIXTURES"/*; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  cmd_file="$dir/cmd"
  expected="$dir/expected.txt"
  [[ -f "$cmd_file" ]] || continue

  # First non-comment, non-empty line → CLI args (do NOT use xargs: GNU xargs
  # defaults to `echo`, so `xargs -n1` on `--help` runs `echo --help`).
  line="$(grep -vE '^\s*(#|$)' "$cmd_file" | head -n1 || true)"
  if [[ -z "$line" ]]; then
    echo "FAIL $name: empty cmd file" >&2
    failed=1
    continue
  fi
  # shellcheck disable=SC2206
  args=($line)
  echo "==> fixture $name: nixup ${args[*]}"

  set +e
  out="$("$BIN" "${args[@]}" 2>&1)"
  code=$?
  set -e

  if [[ -f "$expected" ]]; then
    while IFS= read -r want || [[ -n "$want" ]]; do
      [[ -z "$want" ]] && continue
      if ! grep -Fq -- "$want" <<<"$out"; then
        echo "FAIL $name: expected line not found: $want" >&2
        echo "--- output ---" >&2
        echo "$out" >&2
        failed=1
      fi
    done <"$expected"
  fi

  # help/version must succeed
  if [[ "$name" == "version" || "$name" == "help" ]]; then
    if [[ $code -ne 0 ]]; then
      echo "FAIL $name: exit $code" >&2
      echo "--- output ---" >&2
      echo "$out" >&2
      failed=1
    fi
  fi
done

if [[ $failed -ne 0 ]]; then
  exit 1
fi
echo "all fixtures ok"
