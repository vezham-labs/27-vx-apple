# Filter rules

Turns AdGuard's filter lists into WebKit content-blocking rules for Ark. Ark uses its bundled starter list until an Ark rule endpoint is configured. Run the publisher from a local checkout when updating an Ark rule bucket.

This directory is licensed under the GPL 3.0, unlike the rest of the repo, because it links
[SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib). The rules are derived from
[AdGuard's filter lists](https://github.com/AdguardTeam/AdguardFilters), which are also GPL 3.0, so
they're published under the same license, with the lists they came from in `v1/sources/`.

```sh
swift run -c release build-rules /tmp/rules   # build only
./publish.sh                                  # build and upload
```

To host your own, create an R2 bucket with a public domain, set `BUCKET` for `publish.sh`, and change
`filterRulesUrl` in `vx.deploy.yaml` to your HTTPS URL including `/v1/`.
