# Google Maps MCP

A reference architecture for configuring managed packages containing MCP servers that utilize custom headers for authentication. When packaging the MCP Server Registration, the API key will not be included and instead we need the subscriber to enter their own API key after installation.

In this example, we connect to the [Google Maps Grounding Lite MCP Server](https://developers.google.com/maps/ai/grounding-lite/reference/mcp) using an [API key](https://docs.cloud.google.com/mcp/authenticate-mcp#api-keys-services-that-dont-require-principal) rather than Bearer Token.

## Package Versions

Two versions of this package are published so you can install either one independently or install `0.1.0-1` first and then upgrade to the latest to observe upgrade behavior on a subscriber org.

| Version             | Package Version ID   | Install Link                                            | Notes                                                                                                                                                                                                                                                                                             |
| ------------------- | -------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0.1.0-1` (current) | `04tHs000000iSAFIA2` | `/packaging/installPackage.apexp?p0=04tHs000000iSAFIA2` | Initial release. Ships the External Credential, Named Credential, External Service Registration, and Permission Set required to call the Google Maps Grounding Lite MCP Server. ESR is packaged in the `Incomplete` state — the operations list is hydrated by the platform after install/deploy. |
| `0.2.0-3` (new)     | `04tHs000000iSitIAE` | `/packaging/installPackage.apexp?p0=04tHs000000iSitIAE` | Adds a CSP Trusted Site for `https://mapstools.googleapis.com` and ships the ESR with its tool operations (`search_places`, `lookup_weather`, `compute_routes`) and `Complete` status already populated.                                                                                          |

### What's in both versions

These components are shipped by every version of the package and behave the same way before and after upgrade:

- `externalCredentials/googleMapsMCP` — Custom auth External Credential with the `googleApiKey` Named Principal and the `X-Goog-Api-Key` Custom Header that resolves the subscriber-provided API key.
- `namedCredentials/googleMapsMCP` — `SecuredEndpoint` Named Credential pointing at `https://mapstools.googleapis.com/mcp` and bound to the External Credential above.
- `externalServiceRegistrations/googleMapsMCP` — `ModelContextProtocol` ESR that wires the Named Credential into the MCP Server Registration surface.
- `permissionsets/googleMapsMCP_Perm_Set` — Grants `externalCredentialPrincipalAccesses` to the `googleApiKey` Named Principal and the read access on `UserExternalCredential` that subscribers need to set their key after install.

### What's new in `0.2.0-3`

- **`cspTrustedSites/googleMapsMCP`** — New CSP Trusted Sites for URLs leveraged and returned by Google Maps MCP endpoint. This ensures the agent can display map and route-finding URLs to the user.

### Trying the upgrade path

1. Install `0.1.0-1` in a fresh subscriber org using the install link above and complete the [post-install configuration](#install-and-configure-package).
2. Confirm the MCP Server Registration appears with no tools listed and that calls go out successfully.
3. Install `04tHs000000iSitIAE` over the top of `0.1.0-1` in the same org.
4. Verify the new CSP Trusted Site shows up under Setup → CSP Trusted Sites and that the ESR now exposes `search_places`, `lookup_weather`, and `compute_routes` with `Complete` status.

## Metadata Organization

To package an external MCP Server Registration, four metadata types are required: `externalCredentials`, `externalServiceRegistrations`, `namedCredentials`, and `permissionsets`. The new version additionally ships a `cspTrustedSites` entry for URLs returned by MCP Tools. We'll be primarily working within the External Credential.

Within the External Credential, a Named Principal needs to be defined. The Named Principal will be made up of two parts, the Parameter Name (in our case 'googleApiKey') and one or more internal Authentication Parameters (ours is called 'key'). I recommend keeping these names distinct to make it easier to debug should anything go wrong.

![Authentication Parameters within an External Credential Named Principal](images/externalCredentialNamedPrincipal.png)

Once the Authentication Parameters are set, go back to the External Credential and click 'New' within the Custom Headers section. Here we configure the actual header key and value that will be passed as a part of authenticated calls. The standard format to pass API keys to Google is `X-Goog-Api-Key`. In the value field, use merge field syntax to retrieve the Named Principal credential value `{!$Credential.googleMapsMCP.key}`. The format of this merge field is `"Credential".{External Credential API Name}.{Authentication Parameter Name}` **Note**- even though we are working in a namespaced scratch org, we do not include the namespace of the External Credential when specifying the API name. Additionally, we don't reference the name of the Named Principal Parameter Name (googleApiKey), instead we just reference the key value.

![Finalized External Credential including merge field for auth](images/externalCredential.png)

With this configuration in place, testing and ultimately packaging of the MCP server can take place.

## Install and Configure Package

Once package is installed on a subscribers org, the subscriber must navigate to the External Credential and edit the Named Principal. There, they will add an Authentication Parameter with a Name of 'key' and Value of {Google API Key}.

![Updating the External Credential Authentication Parameter with name/value pair to hold API key](images/postInstallAuthenticationParamConfig.png)
