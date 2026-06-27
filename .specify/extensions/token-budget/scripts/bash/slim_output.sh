#!/usr/bin/env bash
# slim_output.sh — compress noisy CLI output before it reaches the agent context.
#
# Inspired by RTK (Rust Token Killer). This is a pure-bash, dependency-free
# subset that handles the most common spec-kit-relevant cases. For heavier
# workloads, install rtk separately and this script will defer to it.
#
# Usage:
#   slim_output.sh git status
#   slim_output.sh git log -n 50
#   slim_output.sh -- pytest -q
#   slim_output.sh --rule=head_tail --head=20 --tail=20 -- some-noisy-cmd
#
# Strategies (auto-selected by argv[0] of the wrapped command, overridable
# with --rule=...):
#   git_status   : 3-line summary (branch, ahead/behind, changed-files count)
#   git_log      : oneline format, capped at first 30 entries
#   pytest       : keep_fail — drop "PASSED" lines, keep "FAILED"/"ERROR" + summary
#   npm_test     : same as pytest, plus dedupe progress lines
#   head_tail    : keep first/last N lines, replace middle with "[... K lines elided ...]"
#   raw          : no transformation, pass through unchanged

set -euo pipefail

rule=""
head=30
tail=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rule=*) rule="${1#--rule=}"; shift ;;
    --head=*) head="${1#--head=}"; shift ;;
    --tail=*) tail="${1#--tail=}"; shift ;;
    --)       shift; break ;;
    *)        break ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "usage: $(basename "$0") [--rule=NAME] [--head=N] [--tail=N] -- <cmd> [args...]" >&2
  exit 2
fi

cmd="$1"
base="$(basename "$cmd")"

# Auto-pick a rule if none was given. Match against the original argv joined.
if [[ -z "$rule" ]]; then
  joined="$*"
  case "$joined" in
    "git status"*|*"/git status"*)        rule="git_status" ;;
    "git log"*|*"/git log"*)              rule="git_log" ;;
    pytest*|*" pytest"*|*"python -m pytest"*) rule="pytest" ;;
    "npm test"*|"npm run test"*)          rule="npm_test" ;;
    *)                                    rule="head_tail" ;;
  esac
fi

# If real rtk is installed, hand off — it will do better than us.
if command -v rtk >/dev/null 2>&1 && [[ "${TOKEN_BUDGET_PREFER_RTK:-1}" == "1" ]]; then
  exec rtk "$@"
fi

# Capture both stdout and stderr together; we want what the agent would have seen.
# Use a fifo so we can stream-process.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
"$@" >"$tmp" 2>&1 || true   # do not fail this script on the wrapped command's exit code

apply() {
  local r="$1"
  case "$r" in
    git_status)
      local branch ahead_behind dirty
      branch=$(awk -F"'" '/^On branch/{print $0; exit} /^HEAD detached/{print "detached HEAD"; exit}' "$tmp")
      ahead_behind=$(grep -E "(ahead|behind)" "$tmp" | head -1 || true)
      dirty=$(grep -cE "^[[:space:]]+(modified|new file|deleted|renamed):" "$tmp" || true)
      untracked=$(awk '
        /^Untracked files:/   { flag=1; next }
        flag && /^[[:space:]]*$/ { flag=0; next }
        flag && /^[[:space:]]*\(/ { next }                    # skip the "(use git add ...)" hint line
        flag && /^[[:space:]]+[^[:space:]]/ { c++ }
        END { print c+0 }
      ' "$tmp")
      printf '%s\n' "${branch:-On branch (unknown)}"
      [[ -n "$ahead_behind" ]] && printf '%s\n' "$ahead_behind"
      printf 'Changed: %s tracked, %s untracked\n' "$dirty" "$untracked"
      ;;
    git_log)
      # First 30 commits, oneline-ish.
      awk '
        /^commit / { c++; if (c>30) exit; printf "%s ", substr($2,1,7); next }
        /^Author:/ { next }
        /^Date:/   { next }
        /^[[:space:]]*$/ { next }
        /^[[:space:]]+/ && !subj_done { sub(/^[[:space:]]+/,""); print; subj_done=1; next }
        /^commit / { subj_done=0 }
      ' "$tmp"
      total=$(grep -c "^commit " "$tmp" || true)
      [[ "$total" -gt 30 ]] && printf '[... %d more commits elided ...]\n' "$((total-30))"
      ;;
    pytest|npm_test)
      # Drop pass-spam, keep fail and summary lines.
      grep -vE '(PASSED|^\s*ok\s|^npm warn |progress )' "$tmp" | awk '
        /FAILED|ERROR|Error:|FAIL\s/ { print; fails++; next }
        /^=+/                        { print; next }
        /^\s*$/                      { next }
        END { if (fails == 0) print "(all tests passed; details elided)" }
      '
      ;;
    head_tail)
      total=$(wc -l < "$tmp")
      if [[ "$total" -le $((head + tail)) ]]; then
        cat "$tmp"
      else
        head -n "$head" "$tmp"
        printf '[... %d lines elided by token-budget slim ...]\n' "$((total - head - tail))"
        tail -n "$tail" "$tmp"
      fi
      ;;
    raw)
      cat "$tmp"
      ;;
    *)
      cat "$tmp"
      ;;
  esac
}

apply "$rule"
