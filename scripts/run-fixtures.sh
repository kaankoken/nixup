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

  # shellcheck disable=SC2046
  mapfile -t args < <(grep -v '^\s*#' "$cmd_file" | head -n1 | xargs -n1)
  echo "==> fixture $name: nixup ${args[*]}"

  set +e
  out="$("$BIN" "${args[@]}" 2>&1)"
  code=$?
  set -e

  if [[ -f "$expected" ]]; then
    if ! echo "$out" | grep -Fqf "$expected" 2>/dev/null; then
      # allow expected to be a multi-line subset: each non-empty line must appear
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        if ! grep -Fq -- "$line" <<<"$out"; then
          echo "FAIL $name: expected line not found: $line" >&2
          echo "--- output ---" >&2
          echo "$out" >&2
          failed=1
        fi
      done <"$expected"
    fi
  fi

  # default: help/version must succeed
  if [[ "$name" == "version" || "$name" == "help" ]]; then
    if [[ $code -ne 0 ]]; then
      echo "FAIL $name: exit $code" >&2
      failed=1
    fi
  fi
done

if [[ $failed -ne 0 ]]; then
  exit 1
fi
echo "all fixtures ok"
