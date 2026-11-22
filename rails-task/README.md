# rails-task

One-shot Rails task chart. One Kubernetes Job per release.

Covers `db:migrate`, `db:seed`, rake tasks, `rails runner`, and any other one-shot Rails command. For long-running processes (web, worker) use [rails-server](../rails-server).

## TL;DR

```bash
helm install migrate oci://ghcr.io/aypex-io/charts/rails-task --version 0.1.0 \
  --set command='{bundle,exec,rails,db:migrate}'
```

## Design

- **One Job per release.** Run multiple tasks from one umbrella by depending on `rails-task` multiple times with different aliases (`migrate`, `seed`, `rake`).
- **Helm hook aware.** Setting `hook: post-install,post-upgrade` makes the Job a Helm hook AND suffixes its name with a content hash — so ArgoCD tracks each release cycle as a distinct resource instead of leaving the App perpetually "Synced" against a stable-named hook.
- Built on `bitnami/common` — same security defaults, env wiring, and DSN helper as `rails-server` so values shapes match.

## Example: migrate as a post-install hook

```yaml
command: [bundle, exec, rails, db:migrate]
hook: post-install,post-upgrade
hookWeight: "0"
hookDeletePolicy: before-hook-creation
backoffLimit: 3
database:
  enabled: true
  host: my-db-rw
  name: myapp
  userSecretRef: myapp-db
extraEnvVarsSecret: myapp-rails
```

## Example: migrate before the Deployments roll (ArgoCD)

A Helm hook runs after the sync (PostSync), so new pods would start on the old
schema. An ArgoCD Sync hook in an earlier sync wave runs first, and ArgoCD rolls
the later waves only once it completes. If it fails, the sync fails and the
running pods are left as they are.

```yaml
command: [bundle, exec, rails, db:migrate]
argocd:
  hook: Sync
  syncWave: "-5"   # the Deployments are in wave 0; the database must be in an earlier wave
backoffLimit: 3
```

## Example: seed as a one-time tracked Job

```yaml
command: [bundle, exec, rails, db:seed]
# no hook → Job is tracked, runs on first install only (Helm errors on upgrade
# if the Job already exists with same name — use a hook for repeating tasks).
```

## Parameters

See `values.yaml`.
