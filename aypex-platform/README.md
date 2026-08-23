# aypex-platform

Umbrella chart for **aypex.tech**, Aypex's own-brand storefront. A single brand
(not a per-customer fan-out): one Rails image runs as `web` (Puma — Spree admin
and Store API v3) and `worker` (Sidekiq), with `migrate` / `seed` / `rake`
one-shot Jobs, alongside **one** Next.js app that serves the public storefront,
the commerce surfaces *and* the colocated Payload CMS admin.

Consumed by `gitops-aypex/brands/tech/{base,stg,prd}` as an OCI chart.

## Composition

| Alias | Subchart | Role |
|---|---|---|
| `web` | `rails-server` | Puma — Spree admin + Store API v3 |
| `worker` | `rails-server` | Sidekiq (file-freshness liveness probe, no Service) |
| `migrate` | `rails-task` | `rails db:prepare` (post-install/upgrade hook) |
| `seed` | `rails-task` | `rails db:seed` (post-**install** only) |
| `rake` | `rails-task` | env-supplied task (post-install/upgrade hook) |
| `site` | `nextjs` | storefront + commerce surfaces + Payload admin |

One `nextjs` alias, where `spree-platform` has two. The Payload admin is
colocated in the same Next.js app, so there is a single image, a single
Deployment and a single Service — and a block component can import its
generated Payload type directly instead of a hand-maintained copy.

Owned directly by the umbrella: the CNPG cluster and its two databases, the
Dragonfly instances, the ExternalSecrets, the HTTPRoutes, the ReferenceGrant,
and the `payload migrate` Job.

## Databases

**One CNPG cluster, two databases.** `spree` is created by `bootstrap.initdb`
with its owner password taken from the ExternalSecret. `payload` gets a
`Database` CR **and** an entry under `spec.managed.roles` — without the managed
role CNPG mints a random password that the ExternalSecret cannot match, and the
app fails to connect with `28P01`.

The `Database` CR carries `databaseReclaimPolicy: retain`. The field is not
called `reclaimPolicy`; the wrong name is accepted silently and leaves the
Application permanently OutOfSync.

## Routing

| Host | Backend |
|---|---|
| `hostnames.site` (may be a list) | `/rails/active_storage` + `/assets` → `web`; everything else → `site` |
| `hostnames.api` | `web` |
| `hostnames.admin` | `web` (Spree admin, behind Cloudflare Access) |
| `hostnames.cms` | `site`, only `/admin`, `/api`, `/_next` (Payload admin) |

Spree streams product images from S3 through Active Storage proxy URLs, and
those URLs are on the **storefront** host — so those prefixes must reach `web`
or every product image 404s.

`hostnames.cms` is separate from `hostnames.admin` because Spree's admin
already occupies `/admin` on the admin host. Leave it empty to publish no CMS
route at all.

Each route binds only the listener its own hostname intersects. A route that
names a listener it cannot match reports `NoMatchingListenerHostname` while the
other listener keeps serving, which makes it easy to miss.

## Things that will bite

- **ArgoCD must not own the Namespace.** Terraform owns it, along with its PSA
  labels and the ESO SecretStore. `CreateNamespace=true` on the Application
  cascade-prunes every workload in the namespace when the App is removed.
- **Adding a key to the ASM bundle is not free.** The terraform secret carries
  `ignore_changes = [secret_string]`, so a plain apply silently skips a newly
  added key. `-replace` the secret version, or `put-secret-value` by hand.
- **`storageClass: ceph-block`, never `ceph-block-r1`.** The size-1 pool's
  only-copy-on-a-draining-node behaviour wedged a Talos node for 90 minutes.
- **Rebuilding CNPG requires wiping the S3 WAL prefix first**, or the new
  cluster refuses to archive into a foreign timeline.
- **Kargo owns `chartVersion`** in the env overlays. Cut the tag, then stop.
- **Promote the chart to GHCR before merging any overlay that references it.**
  The two cannot land atomically, and values-ahead-of-chart has broken a live
  environment before.

## Release

```bash
helm dependency build aypex-platform
helm lint aypex-platform -f aypex-platform/ci/ci-values.yaml
helm template ci aypex-platform -f aypex-platform/ci/ci-values.yaml

git tag aypex-platform-v0.1.0 && git push origin aypex-platform-v0.1.0
```

The GitHub Action verifies `Chart.yaml`'s version matches the tag, lints,
renders every `ci/*-values.yaml`, and pushes to `oci://ghcr.io/aypex-io/charts`.
