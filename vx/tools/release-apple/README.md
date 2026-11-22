# Apple release tools

The Mac commands build from a Git ref and read `vx.deploy.yaml` from that export.
Use the app's wrapper where available, or pass the app directory as the first argument.

- `install-mac.sh apps/ark [git-ref]` builds and installs a local Mac app.
- `release-mac.sh apps/ark [--local] <version> [git-ref]` packages a Developer ID release. With `--local`, it exports to disk without submitting to Apple's notary service.
- `publish-mac.sh apps/ark <version>` uploads the packaged release to R2 using the deployment settings recorded by the release command.

These scripts expect workspace dependencies, XcodeGen, Xcode, and jq. The release command also uses the signed-in Xcode account, Sparkle signing key, and create-dmg for a notarized release. Cloudflare credentials are supplied through Wrangler. App-specific export, optional WebKit bundling, and release validation hooks stay in the app's `tools/` folder.
