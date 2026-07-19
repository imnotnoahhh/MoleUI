---
name: release-flow
description: "Mole CLI release runbook: distribution channels, pre-flight checklist, capital-V tag publish, curated notes handoff, and release-only pitfalls. Read before any release-flavored task in this repo."
---

# Mole CLI Release Flow

Tag-driven flow. The `release.yml` workflow watches `'V*'` tag pushes (capital `V`), builds amd64 and arm64 binaries on macOS, generates `SHA256SUMS`, attaches build provenance, creates the GitHub Release without notes, then bumps the personal Homebrew tap and opens a Homebrew core PR.

## Distribution channels

| Channel | What ships | Trigger | Automation |
|---|---|---|---|
| Nightly (`mo update --nightly`) | `main` HEAD via `install.sh` | Any commit pushed to `main` | Automatic; no tag or release involved |
| GitHub stable release | amd64/arm64 binaries + `SHA256SUMS` | Push a capital-`V` tag | `release.yml` builds and creates the release; curated notes are a manual follow-up |
| Homebrew personal tap (`tw93/homebrew-tap`) | Formula bump | Same `V*` tag workflow | Automatic; do not re-run manually unless the workflow log shows a failure |
| Homebrew core | Version-bump PR to `Homebrew/homebrew-core` | Same `V*` tag workflow | Automatic PR; merge timing is upstream's |

At the start of any release-flavored task, restate which channels this run will touch and which it will not, and confirm with the maintainer before acting. Channel scope is specified by the maintainer, never inferred.

## Pre-flight checklist

1. `grep '^VERSION=' mole` matches the new version.
2. `SECURITY_AUDIT.md` opening line reflects the new version and date.
3. `git status -s` is empty or only contains intentionally staged release work.
4. `git log origin/main..HEAD --oneline` shows only commits you intend to ship.
5. `./scripts/check.sh --format` and `MOLE_TEST_NO_AUTH=1 MOLE_TEST_JOBS=2 BATS_FORMATTER=tap ./scripts/test.sh` both exit 0.
6. `go test ./cmd/...` and `make build` both pass.

## Tag and publish

```bash
git push origin main
git tag V<version>          # capital V; release workflow ignores lowercase v
git push origin V<version>
```

Wait for the workflow to finish (typically 2 minutes for V1.38.0). The workflow creates the release with assets but `generate_release_notes: false`, so notes must be added in a follow-up step.

After the workflow finishes, verify the release assets before announcing anything: `gh release view V<version> --json assets --jq '.assets[].name'` must list both architecture binaries AND `SHA256SUMS`. Since install verification is fail-closed (V1.47.0), a release without a readable `SHA256SUMS` asset makes every install and `mo update` abort by design; a missing checksums file is a release blocker, not a cosmetic gap.

## Apply curated release notes

The curated-notes flow (bilingual format, `gh release edit` instead of `create`, thanks block, and the six-reaction set) is owned by `.claude/skills/release-notes/SKILL.md`. `.agents/skills/release-notes` is a symlink to that canonical directory for Codex discovery, and its Codex-only invocation policy lives in `agents/openai.yaml`; do not replace the symlink with a copied mirror. Follow that skill; do not duplicate its format details here. Version, codename, and emoji go only in the release title; the body h1 is just `Mole`.

Ritual anchors: before drafting, read the latest stable release body as the hard format template (`gh release view <latest-tag> --json body`); the title takes a codename plus emoji per repo convention (for example `V1.45.0 Quiet 🤫`). After publishing, add all six positive reactions (`+1`, `laugh`, `heart`, `hooray`, `rocket`, `eyes`) with `.claude/skills/release-notes/scripts/post-reactions.sh V<version>` (the script lives inside the skill, not in the top-level `scripts/`), then re-read the release reactions to confirm all six landed.

## Release-notes craft

Format rules (impact ordering, command existence checks, icon semantics, no em dash, no inline PR refs) live in `.claude/skills/release-notes/SKILL.md` under "Format rules". Keep that skill as the single source of truth for notes formatting.

## Release-only pitfalls

- **`gh release create` conflicts with the workflow-created release**: the workflow already creates the release on tag push, so post-tag note publishing must use `gh release edit`, never `create`.
- **Tag prefix is case-sensitive**: `release.yml` filters on `'V*'`. A lowercase `v1.38.0` tag will not trigger the workflow.

Shell and bats pitfalls (bash 3.2 arrays, heredoc `read -n1`, mock bypasses, CI runner quirks) stay in `AGENTS.md` under "Shell and Test Pitfalls"; re-read that section when release work touches shell code or tests.
