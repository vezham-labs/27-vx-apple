# Ark Mac completion batches

This is the execution queue for the Mac pass. The [comparison](../../apps-docs/docs/content/docs/ark/comparison.mdx) remains the source of feature ratings and evidence. A build or upstream review alone does not establish parity. Group compatible changes and run the existing Mac build and focused runtime tour after each substantial batch; do not add new test files or push commits.

## Batch 1: browsing and organization

- **Live folders:** verify signed-in GitHub refresh and owner menus; keep profile data isolated. RSS lifecycle has local fixture evidence.
- **Peek:** verify real navigation and screen-sharing permission; local prompt cancellation and promotion have fixture evidence.
- **Boosts:** complete real-site and picker interaction checks, including dynamic elements, visual accent behavior and accessibility.
- **Easels:** finish staged image annotation, verify pointer drawing, clear/undo, persistence and export placement; image editing and sync remain gaps.
- **Web-app previews:** verify hover, navigation, profile isolation and pointer handoff; service-specific actions remain missing.

## Batch 2: compatibility and migration

- **Chrome extensions / MV2 / MV3 / Firefox / Safari extensions:** verify representative extensions and their actual required APIs; track missing APIs and format limitations individually. These rows overlap; one extension cannot prove all compatibility.
- **Arc import:** verify fresh-import UI and folder visibility; parser and existing fixture evidence already exist.
- **Export Spaces / Shared Collections:** verify file-dialog round trips; hosted links and access controls remain missing.
- **Sync:** verify real cross-device propagation and profile transitions; local folder-coordinator fixtures do not prove device convergence.

## External or informational rows

- **DRM streaming:** verify on a supported signed build and service; record any entitlement or service restriction with evidence.
- **Passkeys:** verify the platform credential entitlement and a real WebAuthn flow; record any external restriction.
- **Address bar, Mobile app, Imported by, Imports from, Built-in AI, Bloat, Maintained:** these use descriptive or non-Yes values; assess their stated behavior and applicability, not as missing checkboxes. Bloat needs a representative before/after workload before claiming an optimization.

## Consolidated verification

After each batch, build once through Nx, run existing relevant BrowserKit checks where shared code changed, and use the existing isolated Mac tour to verify changed behavior and capture previews. Update the comparison and [sync log](ark-sync-log.md) with actual results, unresolved cases, and upstream SHAs. Commit grouped milestones locally only; never push. Mobile and Duo runtime verification follows the Mac-focused pass, with only one simulator running at a time.
