---
name: release-notes
description: Publish curated release notes for a Mole `V<version>` tag. Encodes the compact bilingual format, the gh release edit (not create) flow, reporter/contributor thanks, and the six-reaction set. User-only because publishing is a side effect that touches the public release page.
disable-model-invocation: true
---

# Mole release notes

This skill drives the curated-notes step that runs **after** `release.yml` has finished. The workflow creates the GitHub Release with assets but with `generate_release_notes: false`, so notes must be added in a follow-up `gh release edit` (never `gh release create`, the release already exists, and `create` will conflict).

## Inputs to gather

Before drafting, confirm:

1. **Version**. Capital `V`, e.g. `V1.38.0`. Lowercase `v` does not trigger the workflow and may indicate a botched tag.
2. **CodeName + emoji**. Ask the user. The title format is `V<version> <CodeName> <emoji>`.
3. **Release commit range**. `git log <previous-tag>..V<version> --oneline` gives the raw material.
4. **User-visible behavior changes**. Scan the full commit message bodies (not just subjects) for any narrowed detection, removed feature, or "controlled regression" wording. Examples that have shipped before: the V1.40 VPN narrowing (37a446c9) silently stopped detecting split-tunnel third-party VPNs, the Bluetooth reset removal (357ee057) dropped a flow some users depended on. These belong in notes even when not bug-fix-shaped, because users will hit them in production and won't know what changed.
5. **Issue reporters and PR contributors in this cycle**. Use the merged PRs and fixed issues in the release range. Keep it short, for example `Issue reporters and PR contributors this cycle: @a · @b.` Exclude `tw93` and bots.
6. **Verify release exists**. `gh release view V<version> --repo tw93/Mole --json id,name` should return non-empty. If it doesn't, the workflow hasn't finished, wait, don't `gh release create`.

## Pre-flight (cross-check against CLAUDE.md)

These should already be true if the tag was pushed correctly. Confirm before publishing notes:

- `grep '^VERSION=' mole` matches `<version>`.
- `SECURITY_AUDIT.md` opening line reflects the new version and date.
- `./scripts/check.sh --format` clean.
- `MOLE_TEST_NO_AUTH=1 MOLE_TEST_JOBS=2 BATS_FORMATTER=tap ./scripts/test.sh` exits 0.
- `go test ./cmd/...` and `make build` pass.

If any fail, stop. The notes can wait; a bad release tag cannot.

## Format

Strictly follow the current compact release shape. Compare against a recent release if unsure:
`gh release view V1.43.1 --repo tw93/Mole --json body --jq .body`.

Structure:

```
<div align="center">
  <img src="https://cdn.tw93.fun/pic/cole.png" alt="Mole Logo" width="120" height="120" style="border-radius:50%" />
  <h1 style="margin: 12px 0 6px;">Mole V<version> <CodeName> <emoji></h1>
  <p><em>Deep clean and optimize your Mac.</em></p>
</div>

### Changelog

1. **<English headline>**: <one-sentence English elaboration>.
2. ...

### 更新日志

1. **<中文 headline>**：<一句中文说明>。
2. ...

---

### Mole Mac App

Prefer a GUI? Check out [Mole Mac App](https://mole.fit). The CLI stays free and open source.

---

### Thanks 💖

Issue reporters and PR contributors this cycle: @handle1 · @handle2.

> https://github.com/tw93/Mole
```

### Format rules (all are documented bugs that have shipped before)

- **No em dash anywhere**. Use commas, periods, colons, semicolons, or parentheses.
- **No sponsor list by default**. The current public release style thanks issue reporters and PR contributors for this cycle only.
- **No emoji except the version emoji** in the release title/header and `💖` in the Thanks header.
- **No inline PR refs, no inline `@handle` thanks**. PRs and people belong in the closing Thanks block only.
- **English block first, 中文 block second**. Same numbered order in both blocks. Same number of items.
- **Order items by user-perceived impact, not commit chronology**. Headline change first; internal safety hardening, performance, and bug fixes follow.
- **Verify every command mentioned in the notes actually exists in HEAD**. CLAUDE.md cites `mo check / mo doctor` as a case where a removed command nearly shipped as a "feature".
- **Keep the Mole Mac App cross-link only if it matches the current release style**. Do not turn it into a sales block.

## Publish

Once the user approves the draft:

```bash
gh release edit V<version> --repo tw93/Mole \
  --title "V<version> <CodeName> <emoji>" \
  --notes-file <path-to-draft>
```

**Never** `gh release create`, it conflicts with the release the workflow already made.

Then add the six reactions: `bash scripts/post-reactions.sh V<version>`.

## After publish

- `gh release view V<version> --repo tw93/Mole --web` (open in browser) so the user can eyeball it.
- Remind the user: Homebrew tap + Homebrew core PR are workflow-driven and should already be in flight; do not re-run them manually unless the workflow log shows a failure.

## When NOT to act

This skill is user-invocable only. It must not run unprompted:

- If the user mentions release notes in passing, draft only; do not call `gh release edit`.
- If `gh release view` shows the release does not exist yet, wait. The workflow takes about 2 minutes for an Mn.m.0.
- If the user has not given an explicit "publish" / "提交" signal, stop after the draft.

## Helper scripts

- `scripts/sponsors.sh` - legacy helper for fetching recent sponsors. Do not use it in Mole release notes unless the user explicitly asks for sponsor names.
- `scripts/post-reactions.sh <tag>` - adds the six reactions (`+1`, `laugh`, `hooray`, `heart`, `rocket`, `eyes`) to the release.
