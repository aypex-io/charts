# aypex-io/charts

Generic, reusable Helm charts published as OCI artifacts at `oci://ghcr.io/aypex-io/charts/`.

All charts inherit [`bitnami/common`](https://github.com/bitnami/charts/tree/main/bitnami/common) and follow the Bitnami chart-authoring conventions (values surface, helpers, security defaults).

## Charts

| Chart | Purpose |
|---|---|
| [`rails`](./rails) | Generic Rails app. Single Deployment per release. Compose multiple aliased instances (web + sidekiq + …) in an umbrella. |
| [`nextjs`](./nextjs) | Generic Next.js app. Single Deployment per release. Used for storefronts, Payload CMS, etc. |

## Design intent

The charts here are **focused but highly configurable** — each owns one workload type, exposes a wide values surface, and has no opinions about peers. Consuming umbrellas compose multiple aliased instances and own all cross-cutting infra (databases, ingress/gateway, secrets, jobs).

This is the same shape Bitnami's own charts follow (one chart = one workload type), and it scales naturally: a Rails app with two workers becomes three aliased deps on `rails`, not one chart with three top-level keys.

## Usage

```bash
# Single release
helm install my-app oci://ghcr.io/aypex-io/charts/rails --version 0.1.0

# In an umbrella Chart.yaml
dependencies:
  - name: rails
    version: 0.1.0
    alias: api-web
    repository: oci://ghcr.io/aypex-io/charts
  - name: rails
    version: 0.1.0
    alias: api-worker
    repository: oci://ghcr.io/aypex-io/charts
```

## Versioning & releases

- SemVer per chart, independent versions.
- Breaking values changes → major. New optional values → minor. Helper/template-only fixes → patch.
- Releases are triggered by pushing tags shaped `<chart>-vX.Y.Z` (e.g. `rails-v0.1.0`). The release workflow packages and pushes to GHCR.
- `Chart.lock` and `charts/` are gitignored — `helm dependency update` runs fresh at consumer-side render to avoid the lock-drift trap.

## Local development

```bash
cd rails
helm dependency update
helm lint
helm template t . -f ci/web-values.yaml
helm template t . -f ci/worker-values.yaml
```
