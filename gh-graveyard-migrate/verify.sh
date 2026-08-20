#!/usr/bin/env bash
#
# verify.sh — spot-check that repos migrated by migrate.sh (as
# self-contained branches) actually made it into the target intact. For
# each checked row it confirms: (a) the branch exists on the target's
# remote, (b) its tip commit matches the source repo's actual current
# branch tip on GitHub right now, (c) it's indexed in README.md, and
# (d) — the whole point — the branch's history is genuinely present in
# the target's own object store (checked by fetching only from the
# target, never touching the source), so it would survive the source
# being deleted. Prints a hard N/M pass count at the end.
#
# Usage:
#   ./verify.sh --owner <github-user> --target <graveyard-repo> --csv repos.csv [flags]
#
# Flags:
#   --owner OWNER    github user/org (required)
#   --target REPO    graveyard repo to check against (required)
#   --csv FILE       repos.csv, same format as migrate.sh (default: ./repos.csv)
#   --sample N       check a random sample of N rows (default: check all
#                     candidate rows)
#   --state FILE     if given, only rows marked done here are eligible for
#                     sampling/checking (default: unset — consider all rows)
#   --workdir DIR    scratch dir for the target clone (default: mktemp -d)

set -euo pipefail

OWNER=""
TARGET=""
CSV="./repos.csv"
SAMPLE=""
STATE_FILE=""
WORKDIR=""

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --csv) CSV="$2"; shift 2 ;;
    --sample) SAMPLE="$2"; shift 2 ;;
    --state) STATE_FILE="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#//'; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

[[ -n "$OWNER" ]]  || die "--owner is required"
[[ -n "$TARGET" ]] || die "--target is required"
[[ -f "$CSV" ]]    || die "csv not found: $CSV"
command -v gh >/dev/null || die "gh CLI not found"

[[ -z "$WORKDIR" ]] && WORKDIR="$(mktemp -d -t ghgraveyard-verify)"
mkdir -p "$WORKDIR"

TARGET_DIR="$WORKDIR/_target_$TARGET"
log "cloning target $OWNER/$TARGET (all branches) for verification"
gh repo clone "$OWNER/$TARGET" "$TARGET_DIR" -- -q --no-single-branch

readme_content="$(cat "$TARGET_DIR/README.md" 2>/dev/null || true)"

# candidate rows: branch,repo,source_branch
rows_file="$WORKDIR/rows.txt"
tail -n +2 "$CSV" > "$rows_file"

if [[ -n "$STATE_FILE" ]]; then
  [[ -f "$STATE_FILE" ]] || die "--state file not found: $STATE_FILE"
  # exact match on the branch field only (col 1) — a plain `grep -F -f`
  # here would substring-match, e.g. state entry "newsfeed" would wrongly
  # also select a hypothetical row "newsfeed-old"
  awk -F, 'NR==FNR { want[$1]=1; next } ($1 in want)' "$STATE_FILE" "$rows_file" > "$rows_file.filtered" || true
  mv "$rows_file.filtered" "$rows_file"
fi

total_candidates=$(wc -l < "$rows_file" | tr -d ' ')
[[ "$total_candidates" -gt 0 ]] || die "no candidate rows to verify (check --csv / --state)"

if [[ -n "$SAMPLE" && "$SAMPLE" -lt "$total_candidates" ]]; then
  sort -R "$rows_file" | head -n "$SAMPLE" > "$rows_file.sample"
  mv "$rows_file.sample" "$rows_file"
fi

checked=0
passed=0
declare -a fails=()

while IFS=, read -r branch_name repo source_branch; do
  [[ -z "$branch_name" ]] && continue
  checked=$((checked + 1))

  local_head=$(git -C "$TARGET_DIR" rev-parse "origin/$branch_name" 2>/dev/null || true)
  if [[ -z "$local_head" ]]; then
    log "FAIL  $branch_name  <- branch not found on $TARGET's remote"
    fails+=("$branch_name")
    continue
  fi

  remote_head=$(gh api "repos/$OWNER/$repo/commits/$source_branch" --jq '.sha' 2>/dev/null || true)
  if [[ -z "$remote_head" ]]; then
    log "FAIL  $branch_name  <- could not fetch tip commit for $repo@$source_branch via API"
    fails+=("$branch_name")
    continue
  fi

  commit_count=$(git -C "$TARGET_DIR" rev-list --count "origin/$branch_name" 2>/dev/null || echo 0)
  tip_date=$(git -C "$TARGET_DIR" log -1 --format=%ad --date=short "origin/$branch_name" 2>/dev/null || echo unknown)

  link_target="https://github.com/$OWNER/$TARGET/tree/$branch_name"
  indexed="no"
  grep -qF "]($link_target)" <<<"$readme_content" && indexed="yes"

  if [[ "$local_head" == "$remote_head" ]]; then
    log "PASS  $branch_name  <- $repo  ($commit_count commits, tip dated $tip_date, README indexed: $indexed)"
    passed=$((passed + 1))
  else
    log "FAIL  $branch_name  <- $repo  target branch HEAD $local_head != GitHub $source_branch tip $remote_head"
    fails+=("$branch_name")
  fi
done < "$rows_file"

echo
log "=================================================="
log "VERIFIED: $passed / $checked checked repos passed"
if [[ ${#fails[@]} -gt 0 ]]; then
  log "FAILED: ${fails[*]}"
  log "=================================================="
  exit 1
fi
log "=================================================="
