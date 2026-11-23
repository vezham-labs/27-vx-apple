# Ark upstream sync log

Start each upstream review at the last synced commit. After applying and verifying a sync, add a log entry with the new upstream SHA, the Ark commit, and the changes adopted or skipped.

## Browsa

| Field                    | Value                                                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository     | [jmaorr/Browsa](https://github.com/jmaorr/Browsa)                                                                               |
| Upstream branch          | `main`                                                                                                                          |
| Last synced upstream SHA | [`19eef7990aec8bd5491ef06ffc14928b7a73033f`](https://github.com/jmaorr/Browsa/commit/19eef7990aec8bd5491ef06ffc14928b7a73033f)  |
| Ark checkpoint           | `4610dbf947dcfbcbb21d5ef555fb50a3923baab2`                                                                                      |
| Status                   | Baseline imported. See the [Ark integration notes](../../apps-docs/docs/content/docs/ark/index.mdx) for build and test results. |

## Pending review

- [`ed71db69e6bd0647652563ee91a573b0e593dd2b`](https://github.com/jmaorr/Browsa/commit/ed71db69e6bd0647652563ee91a573b0e593dd2b) was one commit ahead of the baseline in the local Browsa checkout on November 23, 2026. It brings the Mac call window back on screen when its display is gone.

In the Browsa checkout, fetch the current upstream branch and list commits since the last synced SHA.

```sh
git fetch origin main
git log --oneline 19eef7990aec8bd5491ef06ffc14928b7a73033f..FETCH_HEAD
```

## Search

| Field                  | Value                                                                                                                               |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Reference repository   | [driceroland/Search](https://github.com/driceroland/Search)                                                                         |
| Upstream branch        | `main`                                                                                                                              |
| Source SHA for capture | [`6f2b186bfa862d282ee9f424be1dfd5eb8ddc316`](https://github.com/driceroland/Search/commit/6f2b186bfa862d282ee9f424be1dfd5eb8ddc316) |
| Adopted                | WebKit PDF rasterization from `Snap.swift` for Ark Mac’s **Copy Full Page Image** command.                                          |
| UI reference           | Arc 1.174.1 on the local Mac exposes capture through File. Ark also offers the command through ⌘K.                                  |
| Verification           | The Ark Mac build passed. A 500-by-300 WebKit viewport produced a 500-by-1600 PNG that included offscreen content.                  |
| Pending review         | Region capture, split tabs, pin folders, site styles, and iCloud sync.                                                              |
