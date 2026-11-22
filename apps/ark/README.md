# Vezham Ark

Vezham Ark is a browser for iPhone, iPad, and Mac inspired by Arc Browser. We’re building it in public to keep the parts we loved about Arc alive, with a few tweaks of our own. Our aim is to keep Ark open for the long haul, so anyone can follow along, contribute, or carry it forward.

## Development

`App/` contains the mobile client, `Mac/` contains the desktop client, and `Packages/BrowserKit/` holds their shared Swift modules.

Edit `vx.app.yaml` for app identity and version, `vx.deploy.yaml` for platform build settings, and `vx.nav.yaml` for the mobile sidebar’s Settings item.

From the workspace root, run `pnpm nx run ark:generate` to generate the Xcode project. Open `apps/ark/Ark.xcodeproj` and run the Ark scheme on an iOS simulator or ArkMac on your Mac. The corresponding CLI targets are `ark:build-ios` and `ark:build-mac`.

[Third-party notices](THIRD-PARTY-NOTICES.md)
