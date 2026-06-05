# rails

Generic Rails application chart. One Deployment per release.

## TL;DR

```bash
helm install my-rails oci://ghcr.io/aypex-io/charts/rails --version 0.1.0
```

## Design

- **One workload type per release.** Web + sidekiq + any other Rails process are separate releases. In an umbrella chart, depend on `rails` multiple times with different aliases (`spree-web`, `spree-sidekiq`) and value overrides.
- Built on `bitnami/common` — inherits the standard values surface and helpers.
- No opinions about peer infra: no CNPG cluster, no Redis/Dragonfly, no migrate Job. The umbrella owns those.

## Worker release example

```yaml
# values.yaml for a sidekiq release
service:
  enabled: false
command: [bundle, exec, sidekiq]
livenessProbe:
  enabled: false
readinessProbe:
  enabled: false
```

## Parameters

See `values.yaml`.
