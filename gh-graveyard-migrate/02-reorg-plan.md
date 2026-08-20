# GitHub Profile Reorg Plan — ikouchiha47

Goal: cut 137 repos down to a small set of visible, meaningful ones, with **zero history loss** for anything we group. Nothing here is executed yet — review and mark decisions, then we script the migration.

## Technique key
- **submodule**: `git submodule add -b <branch> <old-repo-url> <name>` into a new "graveyard" index repo. The old repo is NOT merged, copied, or rewritten — the graveyard repo just contains a pointer (commit SHA) into the real repo, at its real URL. `cd graveyard/<name> && git log` shows the exact original commits with their exact original dates, because it *is* that repo. (An earlier version of this plan used `git subtree` instead — that technically keeps commits reachable in the object graph, but neither `git log -- path` nor GitHub's own folder view ever surfaces that history, which defeats the entire point. Caught this in testing and switched to submodules before running the real migration.)
- **archive (GitHub)**: click "Archive this repository" — makes it read-only, stays on profile but visually deprioritized, all history/stars intact. Zero effort, fully reversible. A submodule pointing at an archived repo still works fine.
- **keep standalone**: leave as its own repo, just clean up (README, description, maybe unarchive if it should be live).

---

## Target structure (tree view)

```
ikouchiha47/ (GitHub profile, 137 repos → ~40 visible top-level entries)
│
├── ⭐ FLAGSHIP — keep standalone, polish, pin on profile
│   ├── turboc.nvim              (18★, active)
│   ├── clippy                   (12★, active)
│   ├── everm                    (7★)
│   ├── httparty                 (6★)
│   ├── hotel                    (5★ — also early-career, see below)
│   ├── lpm                      (4★, already archived — leave as-is)
│   ├── ssh-manager               (3★)
│   ├── csv-parser-electron      (3★)
│   └── ikouchiha47.github.io    (profile site/blog)
│
├── 🕰️ EARLY-CAREER MILESTONES — keep standalone, permanently exempt from graveyard
│   ├── java_image_filter        (2014, Java image effects lib)
│   ├── hotel                    (2014, full PHP hotel booking system — also ⭐)
│   ├── JustBnW                  (2014, B&W image filter, versioned iterations)
│   ├── ecommerce                (2014, PHP ecommerce prototype w/ sqlite3)
│   ├── wordhistogram            (2014, oldest repo — PHP/sqlite search index)
│   ├── gitview                  (2015, Backbone.js GitHub viewer)
│   └── bhist                    (2020, async browser-history search + Xapian indexing)
│
├── 🚀 ACTIVE — current work, keep standalone
│   ├── cybertron
│   ├── cinestar
│   │   └── cinestar-release     (optional: fold in as a branch, not a repo)
│   ├── huh
│   ├── ultimate-trading-skills
│   ├── roughcut
│   ├── hokedex
│   ├── cookie
│   ├── adaptui
│   ├── swissknife
│   ├── krearts
│   ├── metafold
│   ├── spellfix-builds
│   ├── codekeyboard
│   ├── openscode_studio
│   ├── drcsv
│   ├── shortner                 (Go url shortener — real sharded key-gen design, deploy tooling; not a dup of `shorty`, see note below)
│   └── devtools                 (⚠️ has a stale internal copy of `scratchpad/` — see note below)
│
├── 🧩 NEOVIM PLUGINS — keep standalone (installed by repo URL, can't merge)
│   ├── games.nvim               (2★, active)
│   ├── pairy
│   ├── powercoder
│   ├── typist.nvim
│   └── lua_project_template
│
├── 🧷 KEEP SEPARATE — pulled out of the graveyard on request, standalone
│   ├── timetravel                (2016)
│   ├── vim-rust-ide               (2★, 2016 — vim/rust setup)
│   ├── weather-app                (2016)
│   ├── compilers                  (2016, brainfuck + psi implementations)
│   ├── emulators                  (2024, Zig — Chip-8)
│   ├── hyperion                   (2024, C++ browser project)
│   └── rat                        (2025, Go cli e2e chat)
│
├── 🔒 PRIVATE — keep private, no urgency
│   ├── notorious-app-infra      (pairs with public notorious-app)
│   ├── infrustration-service    (pairs with public infrustration)
│   ├── astronvim
│   ├── iceberg.nvim
│   ├── nova
│   ├── thebackendcompany
│   ├── taxi
│   ├── materialsDB
│   ├── heybro
│   ├── kova-landing
│   ├── gothun
│   ├── droid-forge
│   ├── website-samples
│   ├── file-upload-test
│   ├── stekoverflu
│   ├── shorty
│   └── tzconvert
│
├── 📦 graveyard/  (NEW repo — index of submodules, each with its own real .git history)
│   ├── newsfeed/            → submodule, real repo at github.com/ikouchiha47/newsfeed
│   ├── chathall/            → submodule
│   ├── queryCreator/        → submodule
│   ├── mdb/                 → submodule
│   ├── magazine-rails/      → submodule
│   ├── ngAuth/              → submodule
│   ├── ds-algo/             → submodule (default branch: modularized)
│   ├── redux-react-blog/    → submodule
│   ├── switcher/            → submodule
│   ├── playlist-graphql/    → submodule
│   ├── hackernews/          → submodule
│   ├── simple-express-mongo-passport/  → submodule
│   ├── location-share-web-app/ → submodule
│   ├── angular-dropdown/    → submodule
│   ├── nodejs-net-chat/     → submodule (default branch: tcp-data)
│   ├── youtube-music/       → submodule
│   ├── rdspec/              → submodule
│   ├── alpine/              → submodule
│   ├── grpc_api/            → submodule
│   ├── utility/             → submodule
│   ├── visualizers/         → submodule
│   ├── reviews/             → submodule
│   ├── pdfsj/                → submodule
│   ├── spell-checker/       → submodule (default branch: main)
│   ├── logger/              → submodule
│   ├── curelife/            → submodule
│   ├── desktopfiles/        → submodule
│   ├── brainiac/            → submodule
│   ├── scratchpad/          → submodule (⚠️ see duplicate note below)
│   ├── formfactor/          → submodule (default branch: main)
│   ├── fbrowser/            → submodule
│   ├── knockknock/          → submodule
│   └── remux/               → submodule
│   (source repos optionally archived on GitHub after their submodule is added
│    and verified, not deleted — full history stays live at the original URL;
│    already-archived toy repos `music-recommender` and `grunts` can join the
│    same pass, no rush)
│
└── 🗄️ FORKS (36) — bulk-archive, don't touch otherwise
    ├── miaou, Front-end-Developer-Interview-Questions, Fio, especser, SO-ChatBot,
    │   rxjs-training, gulp-cheatsheet, vertx-examples, javascript, java-design-patterns,
    │   react-router-redux, TinySearchEngine, browser-logos, vim-colors-paramount, moor,
    │   react-native-keychain, Go, Python, cv-maker, gocart, Golang-Project-Structure,
    │   go-advance-concurrency, Awesome-Linux-Software, firefox-csshacks,
    │   startbootstrap-clean-blog-jekyll, ivy, zig-gtk4, AFL, the-algorithm,
    │   zmk-for-keyboards, claude-scientific-skills, ESP32Marauder,
    │   learnxinyminutes-docs, applied-ml
    ├── leetcode, awesome-leetcode-resources   (already archived, no action)
    └── ⚠️ double-check before archiving — these have 1-2★, unusual for an
        untouched fork, might contain your own commits worth keeping visible:
        browser-logos, moor, AFL, Awesome-Linux-Software, Python
```

---

## Three things flagged during content verification, not yet acted on

**`shorty` and `shortner` are not duplicates — different projects, 5 years apart.** `shorty` (2019, Elixir, private) is a bare-bones learning project: one Ecto model, one controller, ~15 files, no deploy tooling. `shortner` (2024, Go, public) is a real system: Dockerfile, nginx config, systemd services, a CLI, and a genuinely designed sharded base58 key-generation scheme documented in its README. Both stay — `shorty` in 🔒 PRIVATE, `shortner` moved into 🚀 ACTIVE.

**`devtools/scratchpad` is a stale duplicate of the standalone `scratchpad` repo.** Cloned both, diffed by file hash: every code file is byte-identical (`auth.js`, `babynames.js`, `data.js`, `index.js`, `package.json`, `package-lock.json`, all of `public/css/*` and `public/js/*`). The standalone repo additionally has `README.md` and `images/` (screenshots) that the `devtools` copy lacks — looks like a plain copy-paste, not a submodule. When ready: delete the `devtools/scratchpad` subfolder, keep the standalone repo as canonical.

**5 repos had no README** (`chathall`, `gitview`, `grunts`, `newsfeed`, `hackernews`) — read their actual source instead of trusting the description. All are exactly what they look like: tutorials/snippets, no hidden surprises, except `gitview` which is now protected in the early-career group above.

---

## Net effect
- **Before**: 137 repos cluttering the profile grid
- **After**: ~41 visible repos (Flagship + Early-career + Active + Neovim plugins + Keep-separate) + 1 new `graveyard` index repo (~31 submodules, each a real repo with its own history) + ~17 private repos (unchanged, don't count against public clutter) + 36 forks archived (hidden from default sort, not deleted)
- **Nothing deleted, nothing rewritten.** Every graveyard entry is the actual original repo, unmodified, at its own URL — `graveyard` just links to them via submodule. Optionally archiving a source repo afterward is read-only and fully reversible; the submodule still works against an archived repo.

## Suggested execution order (once you approve)
1. Bulk-archive the fork list — zero risk, instant win. Double-check the 5 flagged forks first.
2. Create `graveyard`, run `git submodule add` for each graveyard repo via `migrate.sh` (see `gh-graveyard-migrate/`), verify each submodule's HEAD matches GitHub's live tip via `verify.sh`, push.
3. Optionally archive the graveyard source repos on GitHub afterward (not delete — a submodule still works against an archived repo).
4. Clean up README/description on Flagship + Early-career + Active repos, pin top 6 on profile. Write a `gitview` README while at it (currently has none).
5. Resolve the `devtools/scratchpad` duplicate.
6. Decide on private infra-pair merges (optional, no rush).
