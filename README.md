# Google Maps MCP

A reference architecture for configuring managed packages containing MCP servers that utilize custom headers for authentication. When packaging the MCP Server Registration, the API key will not be included and instead we need the subscriber to enter their own API key after installation.

In this example, we connect to the [Google Maps Grounding Lite MCP Server](https://developers.google.com/maps/ai/grounding-lite/reference/mcp) using an [API key](https://docs.cloud.google.com/mcp/authenticate-mcp#api-keys-services-that-dont-require-principal) rather than Bearer Token.

## Package Versions

Released versions are listed below alongside the in-flight version currently being developed on this branch. The `1.0.0` row is a placeholder — the real version label and `04t...` package version id replace it as part of the Phase 4 README rollover once the next version is built and promoted. See [`docs/RELEASE.md`](docs/RELEASE.md) for the full process. You can install any released version independently or step through them in order to observe upgrade behavior on a subscriber org.

| Version   | Package Version ID   | Install Link                                            | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------- | -------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `0.1.0-1` | `04tHs000000iSAFIA2` | `/packaging/installPackage.apexp?p0=04tHs000000iSAFIA2` | Initial release. Ships the External Credential, Named Credential, External Service Registration, and Permission Set required to call the Google Maps Grounding Lite MCP Server. ESR is packaged in the `Incomplete` state — the operations list is hydrated by the platform after install/deploy.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `1.0.0`   | `04tHs000000iSj8IAE` | `/packaging/installPackage.apexp?p0=04tHs000000iSj8IAE` | Adds two CSP Trusted Sites (`https://www.google.com` and `https://maps.gstatic.com`, both img-src) so the agent can render Google Maps links and static map images returned by the MCP server. Adds a post-install Apex handler (`GoogleMapsMCPPostInstall`) that automatically assigns the package permission set to the installer and to the Platform Integration User (identified via the `cloud@{orgId18}` / `noreply@{orgId18}` platform convention). If the packaged permission set is ever deployed without `UserExternalCredential` read access, the handler creates and assigns a `googleMapsMCP_UEC_Access` fallback permission set so server-to-server MCP callouts still resolve the External Credential principal. Every step is idempotent; re-runs and upgrades skip work that is already in place. |

### What's in both versions

These components are shipped by every version of the package and behave the same way before and after upgrade:

- `externalCredentials/googleMapsMCP` — Custom auth External Credential with the `googleApiKey` Named Principal and the `X-Goog-Api-Key` Custom Header that resolves the subscriber-provided API key.
- `namedCredentials/googleMapsMCP` — `SecuredEndpoint` Named Credential pointing at `https://mapstools.googleapis.com/mcp` and bound to the External Credential above.
- `externalServiceRegistrations/googleMapsMCP` — `ModelContextProtocol` ESR that wires the Named Credential into the MCP Server Registration surface.
- `permissionsets/googleMapsMCP_Perm_Set` — Grants `externalCredentialPrincipalAccesses` to the `googleApiKey` Named Principal and the read access on `UserExternalCredential` that subscribers need to set their key after install.

### What's new in `1.0.0`

- **`cspTrustedSites/Google`** — CSP Trusted Site for `https://www.google.com` (img-src) so the agent can render Google-hosted links the MCP server returns.
- **`cspTrustedSites/GoogleStatic`** — CSP Trusted Site for `https://maps.gstatic.com` (img-src) so static map images surfaced in MCP responses load on-platform.
- **`classes/GoogleMapsMCPPostInstall`** — New `InstallHandler` registered via `postInstallScript` in `sfdx-project.json` that runs on every install and upgrade. It assigns the packaged `googleMapsMCP_Perm_Set` to the user who initiated the install.
- **Deterministic Platform Integration User lookup** — The post-install handler resolves the Platform Integration User by the `cloud@{orgId18-lowercase}` Username convention (falling back to the `noreply@{orgId18-lowercase}` Email convention), then assigns the package permission set to that user too so server-to-server MCP callouts have the External Credential principal access they need. This replaces the brittle `Name LIKE 'Platform%'` filter pattern that could match subscriber-created users by accident.
- **Self-healing fallback permission set** — If the packaged permission set is ever deployed without `UserExternalCredential` read access (e.g. subscriber-side metadata stripping), the handler creates a dedicated `googleMapsMCP_UEC_Access` permission set with just that single grant and assigns it to both the installer and the Platform Integration User. The fallback is reused on subsequent runs instead of re-created.
- **Idempotent re-runs** — Each step queries current state before mutating, so re-running the post-install (e.g. on an upgrade where some permissions are already in place) skips no-op steps without error.
- **`classes/GoogleMapsMCPPostInstallTest`** — Ships full test coverage (11 cases, 98% line coverage on the handler) so the package can clear the 75% Apex coverage gate required for promotion.

## Metadata Organization

To package an external MCP Server Registration, four metadata types are required: `externalCredentials`, `externalServiceRegistrations`, `namedCredentials`, and `permissionsets`. Released versions of this package additionally ship `cspTrustedSites` entries for URLs returned by MCP Tools, plus (starting with `1.0.0`) an Apex `classes` directory for the post-install handler. We'll be primarily working within the External Credential.

Within the External Credential, a Named Principal needs to be defined. The Named Principal will be made up of two parts, the Parameter Name (in our case 'googleApiKey') and one or more internal Authentication Parameters (ours is called 'key'). I recommend keeping these names distinct to make it easier to debug should anything go wrong.

![Authentication Parameters within an External Credential Named Principal](images/externalCredentialNamedPrincipal.png)

Once the Authentication Parameters are set, go back to the External Credential and click 'New' within the Custom Headers section. Here we configure the actual header key and value that will be passed as a part of authenticated calls. The standard format to pass API keys to Google is `X-Goog-Api-Key`. In the value field, use merge field syntax to retrieve the Named Principal credential value `{!$Credential.googleMapsMCP.key}`. The format of this merge field is `"Credential".{External Credential API Name}.{Authentication Parameter Name}` **Note**- even though we are working in a namespaced scratch org, we do not include the namespace of the External Credential when specifying the API name. Additionally, we don't reference the name of the Named Principal Parameter Name (googleApiKey), instead we just reference the key value.

![Finalized External Credential including merge field for auth](images/externalCredential.png)

With this configuration in place, testing and ultimately packaging of the MCP server can take place.

## Install and Configure Package

Once package is installed on a subscribers org, the subscriber must navigate to the External Credential and edit the Named Principal. There, they will add an Authentication Parameter with a Name of 'key' and Value of {Google API Key}.

![Updating the External Credential Authentication Parameter with name/value pair to hold API key](images/postInstallAuthenticationParamConfig.png)

## Post-Install Apex

Starting with `1.0.0` the package ships a post-install Apex handler (`GoogleMapsMCPPostInstall`) registered via `postInstallScript` in `sfdx-project.json`. It runs automatically after install or upgrade and is fully idempotent — every step inspects the current state before mutating anything, so re-runs are safe.

What it does:

1. Assigns the packaged permission set `googleMapsMCP_Perm_Set` to the user who initiated the install.
2. Looks up the Platform Integration User by the deterministic platform convention rather than by display name, which avoids accidentally matching a subscriber-created user whose name happens to start with "Platform". The handler resolves the running org's 18-character id (lowercased) via `UserInfo.getOrganizationId()` and queries:
   - `Username = 'cloud@{orgId18-lowercase}'` first, then
   - `Email = 'noreply@{orgId18-lowercase}'` as a fallback,

   then assigns the same packaged permission set to that user so server-to-server MCP callouts have the External Credential principal access they need. The equivalent CLI flow is:

   ```bash
   # 18-char org id, lowercased — e.g. 00dhs000000abcdaba
   ORGID18=$(sf org display --json | jq -r '.result.id' | tr 'A-Z' 'a-z')

   sf data query -q "Select Id, Username, Email from User WHERE Username = 'cloud@${ORGID18}' OR Email = 'noreply@${ORGID18}'"
   sf org assign permset -n googleMapsMCP_Perm_Set -b "cloud@${ORGID18}"
   ```

3. Verifies that the packaged permission set actually carries read access on `UserExternalCredential`. If the deployed permission set is missing that grant — for example because subscriber-side metadata stripping removed it — the handler creates a dedicated `googleMapsMCP_UEC_Access` permission set with just that single grant and assigns it to both the installer and the Platform Integration User. The fallback is reused on subsequent runs rather than re-created.

Subscribers who already configured permissions manually before the upgrade will see the post-install detect the existing assignments and skip those steps without raising errors.

## Contributing & Releases

Day-to-day work happens on `feature/<slug>` branches off `main` and is squash-merged via PR. `main` is always release-ready; package versions are cut from `main` and tagged `vX.Y.Z`.

The full release runbook — branching rules, package version lifecycle, scratch-org validation gates, the README rollover steps, and the smoke-install checklist between cutting a beta and promoting it — lives in [`docs/RELEASE.md`](docs/RELEASE.md). A design spec for the eventual `scripts/release.mjs` helper that wraps the boilerplate is in [`docs/RELEASE_SCRIPT_SPEC.md`](docs/RELEASE_SCRIPT_SPEC.md).

Decisions baked into the runbook (changeable, but the runbook assumes these):

- Only **promoted** package versions are advertised in the [Package Versions](#package-versions) table. Betas live in `sfdx-project.json` `packageAliases` for reproducibility but are not surfaced for installation.
- PRs squash-merge to `main`; each squash commit becomes one entry of "What's new" once the next version ships.
- Per-version `### What's new in X.Y.Z` sections stay inline in this README until three released versions exist, at which point they extract to `CHANGELOG.md`.
- `sf package version create` and `sf package version promote` are always run interactively by a human; the helper script will wrap the file-shuffling around them but won't replace the manual smoke install in between.
