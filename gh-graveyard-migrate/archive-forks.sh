#!/usr/bin/env bash
#
# archive-forks.sh — bulk-archive a list of untouched forks on GitHub.
# Archiving is read-only and fully reversible (unarchive any time);
# it does not delete anything or touch the upstream repo.
#
# Usage:
#   ./archive-forks.sh --owner <github-user> --list forks.txt [--dry-run] [--yes]
#
# forks.txt: one repo name per line, blank lines and lines starting with
# # are ignored.

set -euo pipefail

OWNER=""
LIST=""
DRY_RUN=0
ASSUME_YES=0

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --list) LIST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#//'; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

[[ -n "$OWNER" ]] || die "--owner is required"
[[ -f "$LIST" ]]  || die "list file not found: $LIST"
command -v gh >/dev/null || die "gh CLI not found"

while IFS= read -r repo; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue

  is_fork=$(gh api "repos/$OWNER/$repo" --jq '.fork' 2>/dev/null || echo "unknown")
  is_archived=$(gh api "repos/$OWNER/$repo" --jq '.archived' 2>/dev/null || echo "unknown")

  if [[ "$is_archived" == "true" ]]; then
    log "skip (already archived): $repo"
    continue
  fi
  if [[ "$is_fork" != "true" ]]; then
    log "WARNING: $repo is not a fork (fork=$is_fork) — skipping, double-check your list"
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "[dry-run] would archive: $OWNER/$repo"
    continue
  fi

  if [[ $ASSUME_YES -eq 0 ]]; then
    read -r -p "archive $OWNER/$repo ? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { log "skipped: $repo"; continue; }
  fi

  log "archiving $OWNER/$repo"
  gh repo archive "$OWNER/$repo" --yes
done < "$LIST"

log "done"
