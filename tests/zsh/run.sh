#!/usr/bin/env bash
#
# Run every zsh test in tests/zsh/; exit non-zero if any fails.

set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0
for t in "$dir"/*_test.zsh; do
    printf '%-24s ' "$(basename "$t")"
    out="$(zsh -f "$t" 2>&1)" || status=1
    tail -n1 <<<"$out"
    grep -E '^  FAIL|^    ' <<<"$out" | sed 's/^/  /'
done
exit "$status"
