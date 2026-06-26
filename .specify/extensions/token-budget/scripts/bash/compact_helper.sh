#!/usr/bin/env bash
# compact_helper.sh — bookkeeping for /speckit.token-budget.compact.
#
# This script does not perform content rewriting. The slash-command prompt
# (commands/compact.md) instructs the agent to do that. This script handles
# the deterministic parts: snapshot the original, count tokens before and
# after, and emit a human-readable report row.
#
# Subcommands:
#   backup_if_needed <file>          — copy <file> to <file%.md>.full.md if no backup yet.
#                                      Prints "kept-existing", "created", or "skipped-no-md".
#   snapshot <file>                  — print the current token count of <file> to stdout.
#   summarize <orig> <new>           — print "<file>  <before> → <after> tokens (-X.X%)".
#   has_marker <file>                — exit 0 if <file> contains the compacted marker.
#   stamp <file> <level>             — append the compacted marker to <file>.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESTIMATE="$HERE/estimate_tokens.sh"

cmd="${1:-}"
shift || true

backup_path() {
  local f="$1"
  case "$f" in
    *.md) printf '%s.full.md\n' "${f%.md}" ;;
    *)    printf '%s.full\n'    "$f" ;;
  esac
}

backup_if_needed() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "skipped-missing"
    return 0
  fi
  case "$f" in
    *.md) ;;
    *)    echo "skipped-non-md"; return 0 ;;
  esac
  local b
  b="$(backup_path "$f")"
  if [[ -e "$b" ]]; then
    echo "kept-existing"
  else
    cp "$f" "$b"
    echo "created"
  fi
}

snapshot() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo 0
    return 0
  fi
  "$ESTIMATE" "$f" | cut -f1
}

summarize() {
  local orig="$1" new="$2"
  local before after pct
  before="$(snapshot "$orig")"
  after="$(snapshot "$new")"
  if [[ "$before" -gt 0 ]]; then
    pct=$(awk -v b="$before" -v a="$after" 'BEGIN{printf "%.1f", (a-b)*100.0/b}')
  else
    pct="0.0"
  fi
  # Right-align numbers in 7-char field for readability.
  printf '%-32s %7s → %7s tokens  (%+5s%%)\n' "$(basename "$new")" "$before" "$after" "$pct"
}

has_marker() {
  local f="$1"
  grep -qE '<!--[[:space:]]*token-budget: compacted' "$f" 2>/dev/null
}

stamp() {
  local f="$1" level="${2:-medium}"
  local base
  base="$(basename "$(backup_path "$f")")"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Idempotent: if a marker already exists, replace its line; otherwise append.
  if has_marker "$f"; then
    # Use a portable in-place rewrite.
    local tmp
    tmp="$(mktemp)"
    awk -v rep="<!-- token-budget: compacted (level=$level) on $ts; original at $base -->" '
      /<!--[[:space:]]*token-budget: compacted/ { print rep; next }
      { print }
    ' "$f" > "$tmp"
    mv "$tmp" "$f"
  else
    printf '\n<!-- token-budget: compacted (level=%s) on %s; original at %s -->\n' \
      "$level" "$ts" "$base" >> "$f"
  fi
}

case "$cmd" in
  backup_if_needed) backup_if_needed "$@" ;;
  snapshot)         snapshot "$@" ;;
  summarize)        summarize "$@" ;;
  has_marker)       has_marker "$@" ;;
  stamp)            stamp "$@" ;;
  *)
    cat >&2 <<EOF
usage: $(basename "$0") <subcommand> [args]
  backup_if_needed <file>
  snapshot <file>
  summarize <orig> <new>
  has_marker <file>
  stamp <file> <level>
EOF
    exit 2
    ;;
esac
