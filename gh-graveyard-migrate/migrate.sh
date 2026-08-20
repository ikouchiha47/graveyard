#!/usr/bin/env bash
#
# gh-graveyard-migrate — archive a long tail of old GitHub repos into one
# "graveyard" repo, one at a time, as full self-contained BRANCHES — not
# a merge, not a submodule. `git push` always copies every object a
# branch depends on into the target repo's own object database, so once
# a project's branch is pushed into graveyard, graveyard genuinely owns
# that history. Nothing depends on the original repo continuing to
# exist afterward — this is what makes it safe to delete the source
# repo (unlike a submodule, whose pointer breaks if you do).
#
# Requires: git, gh (authenticated), a repos.csv of the form:
#   branch,repo,source_branch
#   newsfeed,newsfeed,master
#
# Usage:
#   ./migrate.sh --owner <github-user> --target <graveyard-repo> --csv repos.csv [flags]
#
# Flags:
#   --owner OWNER      github user/org that owns both source repos and target (required)
#   --target REPO      name of the graveyard repo to push branches into (required)
#   --csv FILE         path to repos.csv (default: ./repos.csv)
#   --workdir DIR       scratch dir holding the one persistent clone of target (default: mktemp -d)
#   --archive-source    after a verified branch push, run `gh repo archive` on the source
#   --dry-run           print what would happen, touch nothing
#   --yes               skip the per-repo confirmation prompt
#   --state FILE         progress log for resuming (default: ./.migrate-state)
#   --no-readme          skip updating the README archive index after each repo
#
# Idempotent: safe to interrupt and re-run. A repo is skipped if either
# (a) its branch name is recorded in the state file, or (b) the branch
# already exists on the target's remote — the second check self-heals
# if the state file is lost. Nothing here deletes a source repo.
# `--archive-source` only makes the source read-only on GitHub (still
# fully reversible via unarchive) — it is a separate, much safer action
# than deletion; this script never deletes anything itself.

set -euo pipefail

OWNER=""
TARGET=""
CSV="./repos.csv"
WORKDIR=""
STATE_FILE="./.migrate-state"
ARCHIVE_SOURCE=0
DRY_RUN=0
ASSUME_YES=0
UPDATE_README=1

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --csv) CSV="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --state) STATE_FILE="$2"; shift 2 ;;
    --archive-source) ARCHIVE_SOURCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --no-readme) UPDATE_README=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#//'; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

[[ -n "$OWNER" ]]  || die "--owner is required"
[[ -n "$TARGET" ]] || die "--target is required"
[[ -f "$CSV" ]]    || die "csv not found: $CSV"
command -v gh  >/dev/null || die "gh CLI not found"
command -v git >/dev/null || die "git not found"

if [[ -z "$WORKDIR" ]]; then
  WORKDIR="$(mktemp -d -t ghgraveyard)"
  log "using scratch workdir: $WORKDIR"
fi
mkdir -p "$WORKDIR"
touch "$STATE_FILE"

TARGET_DIR="$WORKDIR/$TARGET"
if [[ ! -d "$TARGET_DIR/.git" ]]; then
  log "cloning target repo $OWNER/$TARGET into $TARGET_DIR"
  if [[ $DRY_RUN -eq 0 ]]; then
    gh repo clone "$OWNER/$TARGET" "$TARGET_DIR"
  fi
fi

is_done() { grep -qxF "$1" "$STATE_FILE" 2>/dev/null; }
mark_done() { echo "$1" >> "$STATE_FILE"; }
branch_exists_remotely() {
  [[ $DRY_RUN -eq 1 ]] && return 1
  git -C "$TARGET_DIR" ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1
}

update_readme_index() {
  local branch_name="$1" repo_name="$2"
  [[ $UPDATE_README -eq 0 ]] && return 0
  (
    cd "$TARGET_DIR"
    git checkout -q master
    git pull -q origin master
    link_target="https://github.com/$OWNER/$TARGET/tree/$branch_name"
    if grep -qF "]($link_target)" README.md; then
      # idempotent: already indexed (e.g. a prior run crashed after this
      # step, or self-heal is re-verifying a branch that was already done)
      exit 0
    fi
    line="- [\`$branch_name\`](https://github.com/$OWNER/$TARGET/tree/$branch_name) — originally [\`$repo_name\`](https://github.com/$OWNER/$repo_name)"
    awk -v line="$line" '
      /<!-- ARCHIVE_INDEX_END -->/ { print line }
      { print }
    ' README.md > README.md.new
    mv README.md.new README.md
    git add README.md
    git commit -q -m "graveyard: index $branch_name"
    git push -q origin master
  )
}

# CSV: branch,repo,source_branch  (skip header line)
tail -n +2 "$CSV" | while IFS=, read -r branch_name repo source_branch; do
  [[ -z "$branch_name" ]] && continue

  if is_done "$branch_name"; then
    log "skip (already done): $branch_name"
    continue
  fi

  # self-heal: branch already pushed to target's remote (e.g. state file
  # lost, or a prior run crashed between the push and the README update).
  # Still (idempotently) attempt the README index in case that's the
  # part that didn't complete last time.
  if branch_exists_remotely "$branch_name"; then
    log "skip (branch already on remote, self-healed): $branch_name"
    update_readme_index "$branch_name" "$repo"
    mark_done "$branch_name"
    continue
  fi

  echo
  log "=== $branch_name  <-  $OWNER/$repo (source branch: $source_branch) ==="

  if [[ $ASSUME_YES -eq 0 && $DRY_RUN -eq 0 ]]; then
    read -r -p "  proceed? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { log "  skipped by user"; continue; }
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "  [dry-run] would: git fetch <source-url> $source_branch:refs/heads/$branch_name ; push origin $branch_name ; update README ; ${ARCHIVE_SOURCE:+archive source}"
    continue
  fi

  url="https://github.com/$OWNER/$repo.git"

  # 1. fetch the source's branch tip directly into a new local ref —
  #    no separate scratch clone/checkout needed at all. This pulls
  #    every object that commit depends on into $TARGET_DIR/.git.
  log "  git fetch $url $source_branch:refs/heads/$branch_name"
  git -C "$TARGET_DIR" fetch -q "$url" "$source_branch:refs/heads/$branch_name"

  # 2. verify: the fetched ref matches the source's actual current tip
  #    on GitHub right now (confirmed via API, not just "fetch didn't error")
  local_head=$(git -C "$TARGET_DIR" rev-parse "refs/heads/$branch_name")
  remote_head=$(gh api "repos/$OWNER/$repo/commits/$source_branch" --jq '.sha')
  commit_count=$(git -C "$TARGET_DIR" rev-list --count "refs/heads/$branch_name")
  if [[ "$local_head" != "$remote_head" ]]; then
    git -C "$TARGET_DIR" update-ref -d "refs/heads/$branch_name"
    die "verification failed for $branch_name — fetched HEAD ($local_head) != GitHub $source_branch tip ($remote_head). Not pushing. Investigate before re-running."
  fi
  log "  verify: $branch_name HEAD $local_head matches GitHub $source_branch tip, $commit_count real commits"

  # 3. push the new branch to the target — this is the step that
  #    actually copies the objects into the target's own remote storage
  log "  pushing branch $branch_name to $TARGET"
  git -C "$TARGET_DIR" push -q origin "refs/heads/$branch_name:refs/heads/$branch_name"

  # 4. index it in the README on master (separate commit, doesn't touch
  #    the branch's own history at all)
  update_readme_index "$branch_name" "$repo"

  # 5. optionally archive the source repo on GitHub (read-only,
  #    reversible — this script never deletes anything itself)
  if [[ $ARCHIVE_SOURCE -eq 1 ]]; then
    log "  archiving source repo $OWNER/$repo on GitHub"
    gh repo archive "$OWNER/$repo" --yes
  fi

  mark_done "$branch_name"
  log "  done: $branch_name"
done

log "migration pass complete. state file: $STATE_FILE"
