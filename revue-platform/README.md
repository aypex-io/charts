# revue-platform

Umbrella chart for **Revue**, the headless reviews platform. A single product
(not a per-customer fan-out): one Rails image runs as `web` (Puma — JSON widget/
integration API + Hotwire admin) and `worker` (Sidekiq), with `migrate` + `seed`
one-shot Jobs, on a single CNPG cluster + three dedicated Dragonfly instances.

Consumed by `gitops-aypex/products/revue/{base,stg,prd}` as an OCI chart.

## Composition

| Alias | Subchart | Role |
|---|---|---|
| `web` | `rails-server` | Puma — `/v1/widget`, `/v1/integrations`, `/admin` |
| `worker` | `rails-server` | Sidekiq (file-freshness liveness) |
| `migrate` | `rails-task` | `rails db:prepare` (post-install/upgrade hook, **owner** role) |
| `seed` | `rails-task` | `rails db:seed` (plans) |

In-umbrella infra: CNPG `revue-db` (database `revue`), `redis-queue` (persistent,
Sidekiq), `redis-cache` (LRU, Rails.cache + rack-attack), `redis-cable`
(ActionCable), ExternalSecrets (the `N27a/revue` bundle), and HTTPRoutes for the
`admin` + `api` hosts onto the shared `main` gateway.

## RLS / the two DB roles

Multi-tenant isolation is enforced in the app (`acts_as_tenant`) and backstopped
by Postgres RLS. RLS is bypassed for a table's **owner**, so:

- `migrate`/`seed` connect as the **owner** role `revue` (secret `revue-db`) — they
  run DDL and bypass RLS.
- `web`/`worker` connect as the **non-owner** runtime role `revue_app` (secret
  `revue-app-db`, a CNPG managed role) — RLS engages, and a query that forgot its
  tenant scope cannot cross tenants.

The CNPG **pooler is disabled**: the app sets the per-request `revue.account_id`
GUC at session level, which a transaction-pooling PgBouncer would not preserve.

## Develop

```bash
helm dependency update
helm lint . -f ci/ci-values.yaml
helm template revue-stg . -f ci/ci-values.yaml
```

## Release

Tag `revue-platform-vX.Y.Z` → the repo's `release.yaml` packages and pushes to
`oci://ghcr.io/aypex-io/charts/revue-platform`.
