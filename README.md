# aypex-io/charts

Generic, reusable Helm charts published as OCI artifacts at `oci://ghcr.io/aypex-io/charts/`.

All charts inherit [`bitnami/common`](https://github.com/bitnami/charts/tree/main/bitnami/common) and follow the Bitnami chart-authoring conventions (values surface, helpers, security defaults).

## Charts

| Chart | Purpose |
|---|---|
| [`rails-server`](./rails-server) | Long-running Rails process. Covers web (puma) and worker (sidekiq / solid-queue) — same workload shape, different commands. One Deployment per release. |
| [`rails-task`](./rails-task) | One-shot Rails task: `db:migrate`, `db:seed`, rake tasks, `rails runner`. One Kubernetes Job per release, with Helm hook semantics for ArgoCD-tracked migrations. |
| [`nextjs`](./nextjs) | Next.js app. Used for storefronts, Payload CMS, admin panels. One Deployment per release. |
| [`spree-platform`](./spree-platform) | Umbrella: Spree backend + Next.js storefront + Payload CMS on a shared CNPG cluster + Dragonfly (queue/cache/cable). Multi-tenant. See its [runbooks](./spree-platform/README.md#runbooks). |

## Design intent

The charts here are **focused but highly configurable** — each owns one workload type, exposes a wide values surface, and has no opinions about peers. Consuming umbrellas compose multiple aliased instances and own all cross-cutting infra (databases, ingress/gateway, secrets).

This matches Bitnami's own chart philosophy (one chart = one workload type), and it scales naturally: a Rails app with web + sidekiq + migrate + seed becomes four aliased deps across `rails-server` and `rails-task`, not one chart with conditional logic.

## Usage

```bash
# Single release
helm install my-app oci://ghcr.io/aypex-io/charts/rails-server --version 0.1.0

# In an umbrella Chart.yaml
dependencies:
  - name: rails-server
    version: 0.1.0
    alias: web
    repository: oci://ghcr.io/aypex-io/charts
  - name: rails-server
    version: 0.1.0
    alias: worker
    repository: oci://ghcr.io/aypex-io/charts
  - name: rails-task
    version: 0.1.0
    alias: migrate
    repository: oci://ghcr.io/aypex-io/charts
  - name: nextjs
    version: 0.1.0
    alias: storefront
    repository: oci://ghcr.io/aypex-io/charts
```

## Versioning & releases

- SemVer per chart, independent versions.
- Breaking values changes → major. New optional values → minor. Helper/template-only fixes → patch.
- Releases are triggered by pushing tags shaped `<chart>-vX.Y.Z` (e.g. `rails-server-v0.1.0`). The release workflow packages and pushes to GHCR.
- `Chart.lock` and `charts/` are gitignored — `helm dependency update` runs fresh at consumer-side render to avoid the lock-drift trap.

## Local development

```bash
cd rails-server
helm dependency update
helm lint
helm template t . -f ci/web-values.yaml
helm template t . -f ci/worker-values.yaml
```
