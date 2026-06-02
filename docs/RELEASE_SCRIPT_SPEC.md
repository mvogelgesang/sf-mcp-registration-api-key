# Release Helper Script — Design Spec

**Status:** spec only — not implemented.

A small Node.js (preferred — `package.json` already pulls in dev deps) or shell script that wraps phases 3 and 4 of [`RELEASE.md`](./RELEASE.md). Phase 1 (feature work) and phase 2 (PR + scratch-org validation) stay manual. The smoke installs in step 11 stay manual too — they're the human-in-the-loop gate before the irreversible promote in step 13.

## Goals

- Reduce release-day to "run the script, answer two prompts, push."
- Capture the `04t...` package-version id from `sf package version create` and use it for both the README rollover and the promote call without copy-paste.
- Make every irreversible action gated behind explicit `y/N` confirmation.
- Leave the final `git push origin main --tags` to the human, so the script can never push a tag we don't want pushed.

## Non-goals

- Smoke testing the package. Those installs need a human eye on the org UI; the script just prints the install commands as a reminder.
- Building the version coverage report. `sf package version create --code-coverage` already records it; the script just surfaces the link.
- Hotfix workflow. v1 of the script is for the normal feature-merged-to-main path.

## Suggested location

```text
scripts/
└── release.mjs
```

ESM `.mjs` so we can use top-level `await` and avoid a build step. Invoked as:

```bash
node scripts/release.mjs
```

Or, after adding to `package.json` `scripts`:

```bash
npm run release
```

## Inputs

The script reads, but does not solicit:

| Source              | Field                                                       | Use                                                                                                             |
| ------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `sfdx-project.json` | `packageDirectories[0].versionNumber`                       | The `X.Y.Z.NEXT` we're about to build.                                                                          |
| `sfdx-project.json` | `packageDirectories[0].package`                             | Package alias (`googleMapsMcp`) for `sf package version create -p`.                                             |
| `sfdx-project.json` | `packageAliases`                                            | After `version create` runs, parse the newly added entry to pick up the resolved version label and `04t...` id. |
| `README.md`         | `<NEW_VERSION>` and `<NEW_PACKAGE_VERSION_ID>` placeholders | Targets for the rollover find/replace.                                                                          |
| Environment         | `DEV_HUB_ALIAS` (defaults to `pboDevHub`)                   | Passed as `-v` to the `sf` calls.                                                                               |

The script prompts the user for:

1. **Pre-flight confirmation** — "About to build a new package version of `googleMapsMcp` (currently `0.3.0.NEXT`). Proceed? [y/N]". Bails on anything other than `y`.
2. **Promote confirmation** — after the version is built and smoke-install commands are printed, "Smoke installs passed? Promote `04tHs000000abc` to released? This is irreversible. [y/N]". Bails on anything other than `y`. Bailing here is fine — the unpromoted beta still lives in `sfdx-project.json` and can be promoted later by hand.

## Output sequence

```text
release.mjs
├── 0. Sanity checks
│     ├── git: working tree clean
│     ├── git: current branch is `main`
│     ├── git: HEAD is ahead of origin/main by 0 commits
│     ├── README.md still contains the <NEW_VERSION> placeholder (else bail — nothing to roll over)
│     └── sfdx-project.json parses cleanly
│
├── 1. Pre-flight prompt → user confirms y
│
├── 2. Build phase
│     ├── exec: sf package version create -p googleMapsMcp -x --code-coverage -w 30 -v $DEV_HUB_ALIAS --json
│     ├── parse output → capture SubscriberPackageVersionId (04t...) and versionLabel (e.g. 0.3.0-2)
│     ├── re-read sfdx-project.json to confirm the alias landed in packageAliases
│     └── git add sfdx-project.json && git commit -m "Build googleMapsMcp ${versionLabel}"
│
├── 3. Smoke-install reminder
│     ├── Print the two install commands (fresh + upgrade) with the new 04t injected
│     ├── Print the manual verification checklist (perm set, CSP, ESR status)
│     └── Wait for user to come back
│
├── 4. Promote prompt → user confirms y
│
├── 5. Promote phase
│     ├── exec: sf package version promote -p 04tHs000000... --no-prompt
│     └── On failure, exit non-zero. Do NOT proceed to README rollover — leaves the artifact in a recoverable state.
│
├── 6. README rollover
│     ├── In-memory transform of README.md:
│     │     ├── replace all `<NEW_VERSION>` → versionLabel
│     │     ├── replace all `<NEW_PACKAGE_VERSION_ID>` → 04t...
│     │     ├── in the version table, change `(new)` → `(current)` and the prior `(current)` → `(previous)`
│     │     └── strip the `> TODO: Replace <NEW_VERSION>` callouts (idempotent — remove only those exact lines)
│     ├── Write README.md
│     └── git add README.md && git commit -m "Release v${versionNumber}"
│           (versionNumber is the 3-segment X.Y.Z derived from versionLabel by stripping the -N build suffix)
│
├── 7. Tag
│     ├── git tag -a v${versionNumber} -m "googleMapsMCP ${versionNumber}"
│     └── Print: "Tag created locally. Push with:"
│         echo "  git push origin main --tags"
│
└── 8. Summary
      ├── Released:   googleMapsMcp ${versionLabel}
      ├── Package id: 04t...
      ├── Tag:        v${versionNumber}
      ├── Commits:    2 (build, release)
      └── Next:       git push origin main --tags
```

## Error handling rules

- **Bail before any DML.** All sanity checks (step 0) and prompts (step 1) happen before any `sf` or `git` mutation.
- **Don't auto-rollback.** If `sf package version create` succeeds but the README rollover trips on a missing placeholder, leave the build commit in place and exit non-zero with a message telling the user what to fix manually. Auto-reverting commits hides state from the user.
- **Idempotent re-run.** Running the script a second time with no placeholder in the README should detect "nothing to roll over" in step 0 and exit zero with a friendly message.
- **One promotion per run.** The script promotes exactly the version it just built — never an arbitrary `04t...` from the alias list. If you need to promote an older beta, do it by hand with `sf package version promote`.

## Things the script intentionally won't do

- Push to `origin`. Tag pushes especially are flagged in our git safety rules.
- Edit `CHANGELOG.md` (doesn't exist yet — will be a separate task at the 0.3.0 release boundary).
- Open a browser to verify the package install screen — leaves that to the smoke-install human step.
- Create a GitHub release. We tag locally; release notes can be drafted from the `### What's new` block in the README after the fact.

## Implementation hints (when we're ready to build)

- Use `child_process.spawn` (not `exec`) so live `sf` output streams to the user — `sf package version create` is a long-running command and seeing progress matters.
- Use `--json` on every `sf` call that we need to parse. Treat human-readable output as fire-and-forget.
- For the README transform, use a small `replaceInFile` helper that fails loudly if any of the expected placeholder tokens aren't found (defends against the case where the README has already been partially rolled forward).
- Prompts: `readline` from Node's standard library; no extra dep.
- Add `npm run release` to `package.json` `scripts` once the script lands.

## Testing the script (before relying on it)

- Dry-run mode: `--dry-run` flag that prints every `sf` and `git` command without executing. Confirms the parse logic against current `sfdx-project.json` and `README.md` without burning a real package version.
- Run on a throwaway branch with a copy of `main`'s state, point `--dev-hub-alias` at a sandbox DevHub, and let it cut a beta + promote it against a disposable package. Then revert by deleting the branch.
