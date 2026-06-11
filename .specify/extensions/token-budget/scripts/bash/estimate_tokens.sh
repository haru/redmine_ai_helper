#!/usr/bin/env bash
# estimate_tokens.sh — fast token count for one or more files.
#
# Usage:
#   estimate_tokens.sh <file>...           # one number per file, tab-separated: <count>\t<path>
#   estimate_tokens.sh --total <file>...   # single sum, no path
#   estimate_tokens.sh --json <file>...    # JSON: [{"path": "...", "tokens": N, "bytes": B}, ...]
#
# Strategy:
#   1. If python3 + tiktoken are importable, use cl100k_base (Claude/GPT-4-class encoding).
#   2. Otherwise, fall back to a chars/4 heuristic, which is within ~10% for English
#      Markdown and what every other token-saving tool in the ecosystem uses as a default.
#
# Designed to be fast (<50 ms) and dependency-free at the bash layer. tiktoken use
# is opportunistic; absence is not an error.

set -euo pipefail

mode="lines"
case "${1:-}" in
  --total) mode="total"; shift ;;
  --json)  mode="json";  shift ;;
esac

if [[ $# -eq 0 ]]; then
  echo "usage: $(basename "$0") [--total|--json] <file>..." >&2
  exit 2
fi

# Detect tiktoken once.
have_tiktoken=0
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import tiktoken" >/dev/null 2>&1; then
    have_tiktoken=1
  fi
fi

count_one() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo 0
    return
  fi
  if [[ "$have_tiktoken" -eq 1 ]]; then
    python3 - "$f" <<'PY'
import sys, tiktoken
enc = tiktoken.get_encoding("cl100k_base")
with open(sys.argv[1], "rb") as fh:
    data = fh.read().decode("utf-8", errors="replace")
print(len(enc.encode(data)))
PY
  else
    # chars/4 heuristic — wc -m gives character count.
    local chars
    chars=$(wc -m < "$f" | tr -d '[:space:]')
    echo $(( (chars + 3) / 4 ))
  fi
}

bytes_one() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo 0
    return
  fi
  wc -c < "$f" | tr -d '[:space:]'
}

case "$mode" in
  total)
    total=0
    for f in "$@"; do
      n=$(count_one "$f")
      total=$(( total + n ))
    done
    echo "$total"
    ;;
  json)
    printf '['
    sep=""
    for f in "$@"; do
      n=$(count_one "$f")
      b=$(bytes_one "$f")
      printf '%s{"path":"%s","tokens":%s,"bytes":%s}' "$sep" "$f" "$n" "$b"
      sep=","
    done
    printf ']\n'
    ;;
  lines)
    for f in "$@"; do
      n=$(count_one "$f")
      printf '%s\t%s\n' "$n" "$f"
    done
    ;;
esac
