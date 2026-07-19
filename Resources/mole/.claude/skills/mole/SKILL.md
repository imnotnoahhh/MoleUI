---
name: mole
description: "Drive the Mole CLI (`mo`) safely from an agent: which command answers which question, the machine-readable surfaces (analyze --json, history --json, the dry-run path list), and the rules that keep an automated run from deleting something the user wanted. Read before running any `mo` command on a user's Mac."
---

# Using Mole from an agent

Mole (`mo`) cleans, uninstalls, analyzes, optimizes, and monitors a Mac. It is
a real deletion tool operating on someone's live machine, so the way an agent
uses it differs from the way a human does: never guess, never let a TUI decide,
and never let a destructive command run without the user having seen the list.

## The rules

1. **Preview before you delete. Always.** Every destructive command takes
   `--dry-run`. Run it, read the result, show the user what would go, and only
   then offer the real run. An agent that runs `mo clean` before `mo clean
   --dry-run` has skipped the only step the user can veto.
2. **The user runs the destructive command, not you**, unless they explicitly
   asked you to do it in the current turn. "Clean my Mac" is such an ask;
   "why is my disk full" is not.
3. **Never parse the TUI.** `mo status` and the interactive `mo analyze` are
   full-screen Go programs whose output is drawn, not printed. Piping them
   produces escape-code soup. Use the JSON surfaces below.
4. **Never invent flags.** The command surface is small and listed here; if
   something is not on this page, run `mo <command> --help` and read it, do not
   assume a `--yes` or `--force` exists.
5. **Protection is a whitelist, not an argument.** If the user wants a cache
   kept, the answer is `mo clean --whitelist`, not a hand-rolled `find`. Never
   work around Mole's safety layer with raw `rm`.

## What answers which question

| The user asks | Command |
|---|---|
| "What is eating my disk?" | `mo analyze --json` (whole disk) or `mo analyze <path> --json` |
| "Free up space" | `mo clean --dry-run`, review, then `mo clean` |
| "Remove this app completely" | `mo uninstall --dry-run` then `mo uninstall` |
| "My Mac feels slow" / caches look broken | `mo optimize --dry-run` then `mo optimize` |
| "Clean up my old projects" | `mo purge --dry-run` then `mo purge` |
| "Get rid of downloaded installers" | `mo installer --dry-run` then `mo installer` |
| "What did Mole delete?" | `mo history --json --limit 20` |
| Live CPU / memory / network | `mo status` (hand it to the user; it is a TUI) |

## Machine-readable surfaces

These three are the entire agent-facing API. Everything else is for humans.

**Disk usage.** `mo analyze --json` prints one JSON object: `path`, `overview`,
and `entries[]` of `{name, path, size, is_dir, insight}`. `size` is bytes.
`insight: true` marks an entry Mole considers noteworthy (a large iOS backup, a
runaway cache). Pass a path to scope it: `mo analyze ~/Library --json`.

**Cleanup history.** `mo history --json [--limit N]` (N is 1-200) prints
`logs` (paths of the operations and deletions logs) plus `sessions[]` with
`command`, `started_at`, `items`, `size`, and an `actions` breakdown of
removed / trashed / skipped / failed. This is how you answer "did Mole delete
my file" without guessing: the deletions log has the paths.

**The dry-run path list.** `mo clean --dry-run` prints a summary to the
terminal and writes every candidate path to `~/.config/mole/clean-list.txt`.
Read that file, not the terminal output, when you need to reason about or show
the user exactly what a real run would remove. This list is clean-only: `mo
purge --dry-run` and `mo installer --dry-run` print their candidates to the
terminal and write no file.

## Command notes worth knowing

- `mo clean` also sweeps leftovers from apps the user already deleted. It does
  not touch installed apps; that is `mo uninstall`.
- `mo clean --external <path>` cleans macOS metadata off an external volume.
- `mo purge` removes rebuildable project artifacts (`target/`, `build/`,
  `dist/`, `.next/`). It deliberately does not touch anything that needs a
  network to restore (`node_modules/`, `Pods/`, `venv/`), so a purge is always
  recoverable with a local rebuild. `mo purge --paths` configures which
  directories are scanned; `--include-empty` shows zero-size candidates.
- `mo optimize` refreshes caches and system services. It is the one destructive
  command whose effects are not "files disappear", so say what it will do
  before running it.
- `mo update` self-updates; `mo update --nightly` installs unreleased `main`.
  Do not run either on a user's behalf without being asked.
- `--debug` on any command prints the detailed operation log. Reach for it when
  a command silently did nothing; do not leave it on in normal use.

## When something goes wrong

**`mo clean` deletions are permanent by default.** Cache cleanup removes files
rather than moving them to the Trash, so there is usually nothing to restore.
That is exactly why rule 1 exists: the dry-run is the undo. `mo uninstall` is
the exception: it routes the app and its leftovers through the Trash, so an
uninstalled app is recoverable until the Trash is emptied.

What you do have is a record. `mo history --json` names the deletions log, and
every deletion is one tab-separated line in it: timestamp, mode, size, status,
path. So when a user asks "did Mole take my file", read the log and answer with
the actual line instead of guessing. Then add the path to the whitelist (`mo
clean --whitelist`) so the next run leaves it alone.
