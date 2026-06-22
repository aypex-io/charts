# spree-platform

Umbrella chart for the Aypex Spree commerce platform: the Spree backend
(`rails-server` aliased as `web` + `worker`, `rails-task` as `migrate`/`seed`/
`rake`), the Next.js storefront and Payload CMS (`nextjs`), a shared CNPG
Postgres cluster, and dedicated Dragonfly instances (`redis-queue` /
`redis-cache` / `redis-cable`). Multi-tenant — consumed by gitops with
per-customer overlays (`customers/<slug>/{base,stg,prd}/values.yaml`).

## Runbooks

- [Dragonfly queue persistence & Sidekiq worker liveness](./docs/runbook-dragonfly-persistence-and-sidekiq-liveness.md)
  — durable single-master snapshot-PVC queue + the heartbeat-freshness worker
  liveness probe: design, config, verification (pod-delete survival test), the
  Kargo promote step, and the pitfalls each cost a release.

## Subcharts / aliases

| Alias | Subchart | Workload |
|---|---|---|
| `web` | `rails-server` | Spree puma (HTTP, `/up` probe) |
| `worker` | `rails-server` | Sidekiq (no HTTP; file-freshness liveness probe) |
| `migrate` / `seed` / `rake` | `rails-task` | one-shot Jobs (Helm hooks) |
| `storefront` / `cms` | `nextjs` | Next.js Deployments |

The `redis-queue` / `redis-cache` / `redis-cable` Dragonfly instances and the
CNPG cluster are defined directly in this chart's `templates/`.

## Versioning

Bump `version:` in `Chart.yaml`, merge, then tag `spree-platform-vX.Y.Z` — the
GitHub Action publishes to `oci://ghcr.io/aypex-io/charts/`. Kargo's Warehouse
picks up the new version and promotes it (stg auto, prd manual gate).
