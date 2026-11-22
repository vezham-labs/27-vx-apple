# @vezham/config-apple

Apple app configuration generation for Vx workspaces.

The library validates `vx.app.yaml`, `vx.deploy.yaml`, and `vx.nav.yaml`, then
generates Xcode build settings and the typed Swift navigation source. It follows
the config package structure so it can move into the shared packages repository
without changing its public generation API.

`src/lib/yaml-config.ts` owns YAML input. The `navigation` and `project-config`
modules expose `get*Files` functions for deterministic generation and `generate*`
functions for writing the results. Their CLI files are thin Nx entry points.
