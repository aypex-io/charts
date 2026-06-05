# rails-server

Long-running Rails process chart. One Deployment per release.

Covers both web (puma) and worker (sidekiq / solid-queue) — they're the same workload shape, just different commands and probe configs.

For one-shot tasks (`db:migrate`, `db:seed`, rake tasks, `rails runner`) use [rails-task](../rails-task) instead.

## TL;DR

```bash
helm install my-app oci://ghcr.io/aypex-io/charts/rails-server --version 0.1.0
```

## Design

- **One process per release.** A Rails app with web + sidekiq = two `rails-server` releases (or two aliased deps in an umbrella).
- Built on `bitnami/common` — standard values surface, helpers, security defaults.
- No opinions about peers: no CNPG cluster, no Redis, no Job templates. The umbrella owns those.

## Worker release example

```yaml
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
