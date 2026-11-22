# Vezham Ark

Vezham Ark is a browser for iPhone, iPad, and Mac inspired by Arc Browser. We’re building it in public to keep the parts we loved about Arc alive, with a few tweaks of our own. Our aim is to keep Ark open for the long haul, so anyone can follow along, contribute, or carry it forward.

## Development

`App/` contains the mobile client, `Mac/` contains the desktop client, and [BrowserKit](../../packages-apple/browser-kit/Package.swift) holds their shared Swift modules.

Edit `vx.app.yaml` for app identity and version, `vx.deploy.yaml` for platform build settings, and `vx.nav.yaml` for the mobile sidebar’s Settings item.

From the workspace root, run `pnpm nx run ark:generate` to generate the Xcode project. Open `apps/ark/Ark.xcodeproj` and run the Ark scheme on an iOS simulator or ArkMac on your Mac. The corresponding CLI targets are `ark:build-ios` and `ark:build-mac`.

## Development tools

- Run `pnpm nx run ark-spike:build-mac` to build the [Spike harness](../ark-spike/README.md) with mock browser data.
- See [CallAudio](tools/call-audio/README.md) for the audio experiments and [WebKit bundling](tools/call-audio/webkit/BUNDLING.md) for building and installing the optional custom engine. The default build uses system WebKit.
- See the [filter rule builder](tools/filter-rules/README.md) to build and host rules. Ark uses bundled starter rules by default. Set `filterRulesUrl` in `vx.deploy.yaml` to enable downloads from your HTTPS rule endpoint.
- See [Mac releases](../../apps-docs/docs/content/docs/ark/mac-releases.mdx) for signing, notarization, DMGs and Sparkle feeds. Configure Developer ID signing and Sparkle in `vx.deploy.yaml`. Ark's release commands call the [shared Apple release tools](../../vx/tools/release-apple/README.md). Local development builds leave Sparkle disabled.
- Run [Ark CI](../../.github/workflows/ark-ci.yml) from the Actions tab for native builds and BrowserKit tests.

[Third-party notices](THIRD-PARTY-NOTICES.md)
