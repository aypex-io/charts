# nextjs

Generic Next.js application chart. One Deployment per release.

## TL;DR

```bash
helm install my-nextjs oci://ghcr.io/aypex-io/charts/nextjs --version 0.1.0
```

## Design

- **One workload type per release.** Storefront, CMS, admin, etc. are separate releases. In an umbrella chart, depend on `nextjs` multiple times with different aliases (`storefront`, `cms`) and value overrides.
- Built on `bitnami/common` — inherits the standard values surface and helpers.
- No DB resources, no migrate Jobs — those belong in the umbrella (or a sibling chart). Apps like Payload that need a migrate Job consume `nextjs` for the Deployment and let the umbrella ship the Job.
- `NEXT_PUBLIC_*` env vars are build-time, not runtime — set them in the Docker build, not in chart values.

## Parameters

See `values.yaml`.
