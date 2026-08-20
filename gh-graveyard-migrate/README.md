# gh-graveyard-migrate

Fold a long tail of old, small GitHub repos into one index repo as
**git submodules** — each old repo keeps its own, real, unmodified
`.git` history at its own URL. The "graveyard" repo is just a directory
of links to them, not a merge.

## Why, and why *not* subtree

An earlier version of this tool used `git subtree` to merge everything
into one monorepo. That was wrong and got caught in testing: a
non-squashed `git subtree add` really does preserve every commit and its
original date *in the object database*, but neither `git log --
<path>` nor GitHub's own folder view will ever show that history — both
walk path history against the merge commit's parents, and the
pre-merge commits' trees never contained that path. So in every place a
human would actually go looking ("what's the history of this folder?"),
subtree makes it look like the folder was created today in one commit.
Technically-reachable-in-the-DAG is not the same as preserved, and this
tool used to claim otherwise. It doesn't anymore.

Submodules don't have that problem, because there's no merge and no
rewrite: `graveyard/<name>` is a checkout of the *actual* `<name>` repo
at a specific commit. `cd graveyard/<name> && git log` shows the real
commits with their real dates, because it is that repo. GitHub's UI
understands submodules natively and links straight through to the real
repo at that commit.

## What it does

`migrate.sh` reads a CSV of `dir,repo,branch` rows and, one row at a
time:

1. `git submodule add -b <branch> <url> <dir>` inside your target
   graveyard repo — this clones the source repo directly into
   `<target>/<dir>`. There's no separate scratch clone to manage or
   delete: this checkout is submodule's permanent home, same as any
   other submodule.
2. Verifies the submodule's checked-out commit matches the source repo's
   *actual current* branch tip on GitHub, fetched live via the API — not
   just "did the clone not error."
3. Commits `.gitmodules` + the gitlink change, and pushes immediately —
   one repo per commit, so an interruption never leaves a half-added
   batch, and resuming is just re-running the same command.
4. Optionally archives the source repo on GitHub (`--archive-source`) —
   archiving is read-only and fully reversible, not deletion. A
   submodule pointing at an archived repo still works fine.

Progress is recorded in a state file, so re-running after an
interruption (or a deliberate stop) skips everything already done.

`archive-forks.sh` is a separate, simpler script for bulk-archiving a
list of untouched forks — no submodules involved, just `gh repo archive`
with a fork check and a dry-run mode.

`verify.sh` is a standalone spot-checker you can run any time, on any
subset of the CSV — including a random sample (`--sample 5`) — to prove
N repos actually migrated correctly. For each checked repo it confirms:
the dir is registered in `.gitmodules` pointing at the right upstream
URL, the submodule's checked-out commit matches the repo's live branch
tip on GitHub right now, and reports the commit count and the tip's real
date. It ends with a hard `VERIFIED: N/M checked repos passed` line and
a non-zero exit if anything failed.

## Idempotency

Both `migrate.sh` and re-running it are safe:

- Each successfully-added row is recorded in the state file
  (`--state`, default `./.migrate-state`).
- If the state file is lost, `migrate.sh` still won't double-add: before
  touching a row it checks `.gitmodules` for an exact `path = <dir>`
  entry, and if found marks it done and skips — `git submodule add`
  would otherwise error on a path that's already registered.
- Nothing is ever force-pushed, so a partial run leaves the target repo
  in a perfectly valid, re-clonable state; just re-run the same command.

## Requirements

- [`gh`](https://cli.github.com/) CLI, authenticated (`gh auth login`)
- `git` (submodules are built in, no extra install needed)

## Usage

```sh
# 1. dry run first — prints what would happen, touches nothing
./migrate.sh --owner YOUR_GH_USER --target graveyard --csv repos.csv --dry-run

# 2. for real, prompting per-repo
./migrate.sh --owner YOUR_GH_USER --target graveyard --csv repos.csv

# 3. unattended, and archive each source repo once its add is verified
./migrate.sh --owner YOUR_GH_USER --target graveyard --csv repos.csv \
  --yes --archive-source
```

`repos.csv` format:

```csv
dir,repo,branch
newsfeed,newsfeed,master
ds-algo,ds-algo,modularized
```

`dir` becomes the submodule's directory name in the target repo — usually
just the repo's own name. `branch` is each source repo's actual default
branch — check with `gh api repos/OWNER/REPO --jq .default_branch`,
since not everything is `main`/`master` (this repo's own list has a
`modularized` and a `tcp-data`).

Forks:

```sh
./archive-forks.sh --owner YOUR_GH_USER --list forks.txt --dry-run
./archive-forks.sh --owner YOUR_GH_USER --list forks.txt --yes
```

Spot-check a sample after migrating (or any time later):

```sh
# random sample of 5
./verify.sh --owner YOUR_GH_USER --target graveyard --csv repos.csv --sample 5

# only check rows migrate.sh has actually recorded as done
./verify.sh --owner YOUR_GH_USER --target graveyard --csv repos.csv \
  --state .migrate-state --sample 5

# check everything
./verify.sh --owner YOUR_GH_USER --target graveyard --csv repos.csv
```

Cloning the graveyard repo yourself later, with the real history intact:

```sh
git clone --recurse-submodules https://github.com/YOUR_GH_USER/graveyard.git
cd graveyard/newsfeed && git log   # real commits, real dates
```

## Safety notes

- Nothing here deletes a repo, rewrites history, or force-pushes anything.
- The target repo is only ever pushed with new commits (`git push origin
  HEAD` after each submodule add) — never force-pushed.
- `migrate.sh` verifies the submodule's HEAD against GitHub's live API
  before committing, and refuses to mark a row done if verification fails.
- `--archive-source` is opt-in. Without it, the script only adds
  submodules and pushes — you archive sources yourself once you've
  spot-checked the result.

## License

MIT — see LICENSE.
