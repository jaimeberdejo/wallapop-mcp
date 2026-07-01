# ADR-0004: Reject out-of-range/nonsensical search inputs at the Zod schema layer

Date: 2026-07-02
Decision: Added range/positivity constraints to the `search` tool's Zod `inputSchema`
(`minPrice`/`maxPrice` non-negative, `distanceInKm` positive, `latitude` in [-90,90],
`longitude` in [-180,180], `maxResults` a non-negative integer) plus a handler-level
`minPrice <= maxPrice` cross-field check, replacing the prior silent pass-through/empty-result
behavior documented in `BUGS_AND_RISKS.md` items #83-89/#91.
Why: `buildSearchRequest` has no validation and forwards nonsensical values (e.g.
`latitude: 999`, `minPrice: -50`) straight to Wallapop's API with no useful signal to an LLM
caller about why a search silently returned nothing or errored upstream; rejecting early with a
field-named error is more useful than round-tripping a doomed request. Rejected alternative:
clamping values instead of rejecting — rejected because clamping silently changes the caller's
intent (e.g. a typo'd `latitude: 990` becoming `90`) without telling them, which is worse for an
LLM client than an explicit, correctable error.
