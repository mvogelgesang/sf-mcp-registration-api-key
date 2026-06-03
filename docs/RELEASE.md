# Release Runbook — googleMapsMCP

Operating instructions for cutting and shipping a new managed-package version. The decisions baked into this runbook are:

1. **Squash-merge** every PR into `main`.
2. **Only promoted versions are advertised as installable** in `README.md`. Betas are tracked in `sfdx-project.json` for reproducibility but are not surfaced in the version table.
3. **Per-version "What's new" blocks stay inline in `README.md` until the third released version**, at which point they extract to `CHANGELOG.md` (see "Future improvements" below).
4. **Cutting and promoting a version is a manual human-in-the-loop step.** A helper script (specced in [`RELEASE_SCRIPT_SPEC.md`](./RELEASE_SCRIPT_SPEC.md)) will wrap the boilerplate when we're ready to build it; the actual `sf package version create` / `sf package version promote` calls always run interactively for now.

## Branching paradigm

Trunk-with-feature-branches. `main` is always tag-able.

| Branch                    | Purpose                                                                          | Lifetime      |
| ------------------------- | -------------------------------------------------------------------------------- | ------------- |
| `main`                    | Released or release-ready code. Tagged on every shipped version.                 | Permanent     |
| `feature/<slug>`          | One feature, bug fix, or refactor. Branched from `main`, merged back via squash. | Days to weeks |
| `hotfix/<version>-<slug>` | Single-fix patch on top of a released version. Same merge rules as `feature/*`.  | Hours to days |

Rules:

- No commits directly to `main`. Everything goes through a PR.
- A PR cannot merge until the scratch-org test cycle (deploy + `sf apex run test`) is green and Apex coverage is ≥90% on every modified class.
- Squash-merge so each entry in `main`'s history is one logical change.
- Rename existing legacy branches (`v1`, `postInstall`) to `feature/v1-csp-esr` and `feature/post-install-apex` on next touch; not required retroactively.

## Package version lifecycle

A version transitions through four states; each transition has a concrete artifact change.

```text
Planned → Built → Released → Superseded
```

| State          | Trigger                               | Artifact change                                                                                                                                                                   |
| -------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Planned**    | Feature branch opened                 | `sfdx-project.json` `versionNumber` bumped to `<X.Y.Z>.NEXT` and `ancestorVersion` set to the last Released. README placeholder row + "What's new in `<NEW_VERSION>`" stub added. |
| **Built**      | `sf package version create` succeeds  | New `04t...` alias auto-appended to `sfdx-project.json` `packageAliases`. README unchanged.                                                                                       |
| **Released**   | `sf package version promote` succeeds | README rollover commit + git tag `vX.Y.Z`.                                                                                                                                        |
| **Superseded** | The next version reaches Released     | "(current)" label shifts to the new row; the row that was "(current)" becomes "(previous)" or rolls into a collapsed bucket once `CHANGELOG.md` exists.                           |

Betas (`-1`, `-2`, `-3`…) are intermediate Built artifacts. They are installable but are **not** added to the README version table. The latest beta's `04t...` lives in `sfdx-project.json` for reproducibility and so test installs work, and that's the only place it appears.

## Step-by-step release runbook

Each step is one command or one commit. Treat the order as the contract — skipping the Phase 3 smoke installs before the Phase 4 promote is what causes irreversible mistakes, since `sf package version promote` cannot be undone. Steps are numbered per phase; cross-references use the form "Phase 3 step 3".

### Phase 1 — Develop on a feature branch

1. **Branch:** `git checkout -b feature/<slug>` from `main`.
2. **Bump version & add placeholders** in the same first commit:
   - In `sfdx-project.json`, set `versionName`/`versionNumber` to the next planned version (e.g. `ver 0.3` / `0.3.0.NEXT`) and `ancestorVersion` to the last Released version (e.g. `0.2.0`).
   - In `README.md`, append a `<NEW_VERSION>` row to the version table and a `### What's new in <NEW_VERSION>` stub. Don't delete the equivalent stubs left over from the previous in-flight release until Phase 4 — Phase 1 only _adds_ the next-version stubs.
3. **Develop, write tests, commit normally.** Apex test classes live in `force-app/main/default/classes/` next to the class under test.

### Phase 2 — Validate on a fresh scratch org

For every PR — _not_ just for releases — to keep `main` permanently shippable.

1. **Create the scratch org:**

   ```bash
   ALIAS="gmMcpTest_$(date +%Y%m%d_%H%M%S)"
   sf org create scratch \
     -f config/project-scratch-def.json \
     -a "$ALIAS" \
     -v pboDevHub \
     -d -y 1 -w 15
   ```

2. **Deploy source:** `sf project deploy start -o "$ALIAS"`.
3. **Run Apex tests with coverage:**

   ```bash
   sf apex run test -o "$ALIAS" \
     -l RunSpecifiedTests \
     -t GoogleMapsMCPPostInstallTest \
     -c -r human -w 15
   ```

   Required outcome: 100% pass rate, ≥90% coverage on every modified class, ≥75% org-wide.

4. **Open the PR** to `main`. Title is the line that will appear in "What's new" once released. Description includes:
   - Pasted test summary table from Phase 2 step 3.
   - The scratch org alias used for validation (so a reviewer can re-create or inspect it).
   - The list of metadata types touched.
5. **Squash-merge** when approved.

### Phase 3 — Cut the package version from `main`

1. **Sync `main` locally:** `git switch main && git pull --ff-only`. Confirm working tree is clean.
2. **Build the package version:**

   ```bash
   sf package version create \
     -p googleMapsMcp \
     -x \
     --code-coverage \
     -w 30 \
     -v pboDevHub
   ```

   The command appends a new `googleMapsMcp@X.Y.Z-N: 04tHs...` entry to `sfdx-project.json` `packageAliases`. Capture the `04t...` id from the output — you'll need it for Phase 3 step 3 and Phase 4 step 1.

3. **Smoke install the new beta** in a fresh subscriber-like org _and_ an upgrade scenario. The upgrade test is the one that catches breakage subscribers will hit:

   ```bash
   # Fresh-install smoke
   sf org create scratch -f config/project-scratch-def.json -a smoke_fresh -v pboDevHub -d -y 1 -w 15 -m
   sf package install -o smoke_fresh -p 04tHs000000... -w 15 -r

   # Upgrade-path smoke
   sf org create scratch -f config/project-scratch-def.json -a smoke_upgrade -v pboDevHub -d -y 1 -w 15
   sf package install -o smoke_upgrade -p <previous_released_04t> -w 15 -r
   sf package install -o smoke_upgrade -p 04tHs000000... -w 15 -r
   ```

   In both orgs, manually verify:
   - All metadata types listed in `README.md` "What's in both versions" are present.
   - Post-install Apex assigned the package permission set to the installer and (if present) the `cloud@{orgId18}` Platform Integration User.
   - The CSP Trusted Sites appear under Setup → CSP Trusted Sites.
   - The ESR shows status `Complete` with all expected operations.

4. **Commit the `sfdx-project.json` alias addition:** `git add sfdx-project.json && git commit -m "Build googleMapsMcp <X.Y.Z-N>"`.

### Phase 4 — Promote and roll the README forward

Only proceed past Phase 4 step 1 once Phase 3 step 3 passed cleanly. Promotion is **irreversible**.

1. **Promote:**

   ```bash
   sf package version promote -p 04tHs000000... --no-prompt
   ```

2. **README rollover commit** — single commit that finalizes the released version's documentation:
   - Replace every `<NEW_VERSION>` in `README.md` with the real version label (e.g. `0.3.0-2`).
   - Replace every `<NEW_PACKAGE_VERSION_ID>` with the real `04t...`.
   - In the version table:
     - The row that was "(current)" → "(previous)" (or remove its `(current)` annotation if you prefer just-version labels).
     - The row that was "(new)" → "(current)".
   - In the upgrade-path section, update the "install over the top" line to reference the newly current `04t...` (and the previous one as the baseline to install first).
   - Concretize the `### What's new in <NEW_VERSION>` heading to `### What's new in <X.Y.Z>` and keep the bullets — this section becomes the durable record for that release.
   - **Do not** delete the previous release's "What's new" section. Both stay in the README until the third release triggers extraction to `CHANGELOG.md`.

   Commit message: `Release v<X.Y.Z>`.

3. **Tag and push:**

   ```bash
   git tag -a v<X.Y.Z> -m "googleMapsMCP <X.Y.Z>"
   git push origin main --tags
   ```

## README touchpoints summary

What changes in `README.md` and when:

| Section                                 | Touch in Phase 1                                                                                               | Touch in Phase 4                                                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `## Package Versions` table             | Append `<NEW_VERSION>` row with placeholders                                                                   | Replace placeholders; shift `(current)` ↔ `(previous)`                                                                                                    |
| `### What's new in <NEW_VERSION>`       | Add new stub with bullets describing the change                                                                | Replace heading placeholder with real version; bullets stay verbatim                                                                                      |
| `### Trying the upgrade path`           | Reference the _previous_ released version as the baseline and `<NEW_PACKAGE_VERSION_ID>` as the upgrade target | Replace placeholder with real `04t...`                                                                                                                    |
| `## Post-Install Apex` `> TODO` callout | n/a (already there)                                                                                            | Remove the `> TODO: Replace <NEW_VERSION>` line once the runbook is established. After this runbook is committed, future releases won't need the callout. |

## Future improvements

These are not part of the runbook today but are committed to in order of when they unlock:

1. **`CHANGELOG.md` extraction** (after 0.3.0 ships). When the README has three released versions, extract every `### What's new in X.Y.Z` block to `CHANGELOG.md` in [Keep-a-Changelog](https://keepachangelog.com/) format. The README's version table stays; it gains a "See [`CHANGELOG.md`](./CHANGELOG.md) for per-version detail" line where the inline sections were. Rolling forward from 0.4.0 onwards then only edits the CHANGELOG and the table.
2. **Helper script** (`scripts/release.mjs`). Specced in [`RELEASE_SCRIPT_SPEC.md`](./RELEASE_SCRIPT_SPEC.md). Wraps phases 3 and 4 of this runbook, leaving phase 1, 2, and the smoke installs manual.
3. **CI on PRs.** GitHub Action that creates a 1-day scratch org, deploys, runs the Apex tests, posts the coverage table as a PR comment. Blocks merge below the 90%/100%-pass gate. Out of scope until the helper script lands.

## Quick reference — common commands

| What                            | Command                                                                                              |
| ------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Spin a one-day scratch org      | `sf org create scratch -f config/project-scratch-def.json -a <alias> -v pboDevHub -d -y 1 -w 15`     |
| Deploy source                   | `sf project deploy start -o <alias>`                                                                 |
| Run package tests with coverage | `sf apex run test -o <alias> -l RunSpecifiedTests -t GoogleMapsMCPPostInstallTest -c -r human -w 15` |
| Build a package version (beta)  | `sf package version create -p googleMapsMcp -x --code-coverage -w 30 -v pboDevHub`                   |
| Install a beta in a smoke org   | `sf package install -o <alias> -p 04tHs000000... -w 15 -r`                                           |
| Promote a beta to released      | `sf package version promote -p 04tHs000000... --no-prompt`                                           |
| Tag a release                   | `git tag -a vX.Y.Z -m "googleMapsMCP X.Y.Z" && git push origin main --tags`                          |
| Clean up an old scratch org     | `sf org delete scratch -o <alias>`                                                                   |
