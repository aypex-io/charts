# revue-platform

Umbrella chart for **Revue**, the headless reviews platform. A single product
(not a per-customer fan-out): one Rails image runs as `web` (Puma — JSON widget/
integration API + Hotwire admin) and `worker` (the pgbus supervisor), with
`migrate` + `seed` one-shot Jobs, on a single CNPG cluster. Previews add a `sample` Job.

pgbus runs **both background jobs and realtime Turbo streams on Postgres/PGMQ**,
and Rails.cache is Solid Cache, also on Postgres: no Sidekiq and no Redis of any kind.

Consumed by `gitops-aypex/products/revue/{base,prd}` as an OCI chart, and by the
`revue-preview` ApplicationSet (`products/revue/preview`): one release per PR labelled
`preview`, all in the shared `revue-preview` namespace. Revue has no staging (since
2026-11), so **a release of this chart runs on previews first**. Kargo's `preview`
Stage points every preview at it (`products/revue/preview/version.yaml`), and prd
takes it automatically once a preview has run it Synced/Healthy for 10 minutes. With no
preview open it waits, so label a revue PR `preview` to move it along.

## Composition

| Alias | Subchart | Role |
|---|---|---|
| `web` | `rails-server` | Puma — `/v1/widget`, `/v1/integrations`, `/admin` |
| `worker` | `rails-server` | pgbus supervisor (jobs + streams; no external probe — self-supervising) |
| `migrate` | `rails-task` | `db:prepare && db:install_pgmq && db:enforce_tenancy` (ArgoCD Sync hook in wave -5: after the CNPG Cluster (-8), **before** the Deployments (0); **owner** role) |
| `seed` | `rails-task` | `rails db:seed` (plans) |
| `sample` | `rails-task` | `rails revue:demo` (sample data; idempotent). **Previews only**: off unless `sample.enabled`. PostSync hook weight 5, after seed (0) |

**Workload switches (0.8.0+):** `web.enabled`, `worker.enabled`, `migrate.enabled`
and `seed.enabled` (and `sample.enabled`) turn each workload on or off. All but
`sample` default to on, and prd sets none of them. A preview starts with all five
off, so only its CNPG Cluster exists: the routes and their ReferenceGrant follow
`web.enabled` (0.8.2+), so a waiting preview stays Healthy and its hosts 404
instead of pointing the gateway at a web Service that isn't there. Once the PR's image has
been built, Kargo writes a per-PR values file that turns them on together with
the image tag. The first sync then migrates (Sync hook, wave -5) and starts the
Deployments with an image that already exists: no ImagePullBackOff, no crash
loop while the database comes up. Turning a switch off on a live release deletes
that workload.

In-umbrella infra: CNPG `revue-db` (database `revue`), `redis-cache` (LRU,
Rails.cache + rack-attack), ExternalSecrets (the `N27a/revue` bundle), and
HTTPRoutes for the `admin` + `api` hosts onto the shared `main` gateway (one route
when `hostnames.api == hostnames.admin`, as on a preview). Jobs and
streams need no Redis — they ride the CNPG primary via PGMQ + LISTEN/NOTIFY.

## RLS / the two DB roles

Multi-tenant isolation is enforced in the app (`acts_as_tenant`) and backstopped
by Postgres RLS. RLS is bypassed for a table's **owner**, so:

- `migrate`/`seed` connect as the **owner** role `revue` (secret `revue-db`) — they
  run DDL and bypass RLS. The owner is also a CNPG managed role, only to make it a
  member of `revue_app`: the worker creates the pgbus queue tables as `revue_app`,
  and a PGMQ upgrade migration run as the owner has to alter them.
- `web`/`worker` connect as the **non-owner** runtime role `revue_app` (secret
  `revue-app-db`, a CNPG managed role) — RLS engages, and a query that forgot its
  tenant scope cannot cross tenants.

The CNPG **pooler is disabled**: the app sets the per-request `revue.account_id`
GUC at session level, which a transaction-pooling PgBouncer would not preserve.

## Develop

```bash
helm dependency update
helm lint . -f ci/ci-values.yaml
helm template revue-ci . -f ci/ci-values.yaml
bash ci/check-preview-releases.sh   # two preview releases share a namespace without collisions
```

**Previews share one namespace**, so everything the chart renders must be
release-scoped. Subchart objects, routes and the ReferenceGrant are named from the
release. Per PR, the ApplicationSet sets `cnpg.name` and each workload's
`database.host`. `ci/check-preview-releases.sh` fails on any shared name.

## Release

Tag `revue-platform-vX.Y.Z` → the repo's `release.yaml` packages and pushes to
`oci://ghcr.io/aypex-io/charts/revue-platform`.
