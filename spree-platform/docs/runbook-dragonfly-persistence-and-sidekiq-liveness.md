# Runbook — Dragonfly queue persistence & Sidekiq worker liveness

Reusable guide for adding **durable Sidekiq queues** (Dragonfly snapshot persistence)
and a **Sidekiq worker liveness probe** to a `spree-platform` tenant — or to any
chart that runs Sidekiq against a Redis-compatible store. Both were rolled out on
`tkf` (spree-platform 0.9.x + backend ≥ v0.5.3); this captures the design,
the exact config, the pitfalls, and how to verify each one.

The two are independent — implement either alone — but a Sidekiq deployment that
cares about not losing jobs wants both: persistence so a restart doesn't drop the
queue, and the liveness probe so a wedged worker gets recycled.

---

## Part 1 — Dragonfly queue persistence

### When to use
The Sidekiq queue store (Dragonfly/Redis) holds enqueued + scheduled + retry jobs.
Run **without eviction** (losing a job is data loss) **and with persistence**, or a
pod restart — routine in k8s (rollout, node drain, eviction, OOM) — silently wipes
the queue. The cache/cable instances are the opposite: ephemeral, eviction-tolerant,
**no** persistence.

### Design (single master + snapshot PVC)
- **`replicas: 1`, hard-pinned.** Dragonfly has no replication here, so >1 pod behind
  one Service = independent masters splitting the queue (stranded jobs, duplicate
  cron). The RWO PVC also makes >1 impossible.
- **`strategy: Recreate`** — an RWO PVC can't be mounted by two pods, so the old pod
  must release it before the new one mounts.
- **RWO PVC at `/data`** + Dragonfly snapshot flags: load-on-start, save-on-graceful-
  shutdown, plus a periodic cron for ungraceful death.
- **Pin the Dragonfly image** — never `:latest` in prod.

That shape — `Deployment + RWO PVC + strategy: Recreate` — is the right one for any
single-writer store in this chart. (It was previously described here as "the in-chart
Meilisearch pattern"; that subchart was removed in 1.2.2, so the pattern is stated
directly rather than by reference.)

### Config
Deployment container args (`templates/redis-queue.yaml`):
```yaml
args:
  - --logtostderr
  - --proactor_threads={{ .Values.redisQueue.proactorThreads }}
  - --version_check=false
  - --dir=/data
  - --dbfilename=dump                       # fixed name → one overwriting dump
  - {{ printf "--snapshot_cron=%s" .Values.redisQueue.persistence.snapshotCron | quote }}
volumeMounts:
  - { name: data, mountPath: /data }
# spec: replicas: 1, strategy.type: Recreate, + a RWO PVC named <release>-redis-queue
```
Values:
```yaml
redisQueue:
  replicaCount: 1            # retained for back-compat but IGNORED — template pins 1
  persistence:
    size: 2Gi               # queue is tiny; snapshots are MB
    storageClass: ceph-block-r1
    snapshotCron: "*/5 * * * *"
```

### Pitfalls (each cost a release on the tkf rollout)
1. **Quote any arg ending in a colon.** `- --shard_round_robin_prefix=queue:` parses
   as a YAML **map** (`{"...queue": null}`), not a string → API server rejects the
   Deployment ("cannot unmarshal object into args of type string"). `helm template`
   emits the text fine; only **YAML-parsing** the render catches it:
   ```bash
   helm template . -f base.yaml -f env.yaml | python3 -c '
   import sys,yaml
   for d in yaml.safe_load_all(sys.stdin):
     if d and d.get("kind")=="Deployment" and "redis-queue" in d["metadata"]["name"]:
       for a in d["spec"]["template"]["spec"]["containers"][0]["args"]:
         assert isinstance(a,str), ("NON-STRING ARG", a)'
   ```
2. **`--dbfilename` with no `{timestamp}`** → a single overwriting `dump`, so startup
   loads a deterministic file and snapshots don't accumulate.
   **This regressed in the operator rewrite and cost an outage.** The operator
   supplies `--dir` and `--snapshot_cron` but *not* `--dbfilename`, and the
   binary's default is `dump-{timestamp}` (`dragonfly --helpfull`) — so every
   cron tick wrote a new file and nothing pruned them; there is no retention
   flag. `aypex-tech-stg` filled its 2Gi queue PVC on 2026-08-30 (2062 files)
   and then failed *every* snapshot for 11 days, leaving the queue effectively
   unpersisted. Restored in aypex-platform 0.1.4 / spree-platform 1.2.4. When
   auditing a tenant, `ls /dragonfly/snapshots` should show ONE `dump-*.dfs`
   set, not a timestamped series:
   ```bash
   kubectl -n <ns> exec redis-queue-0 -c dragonfly -- ls /dragonfly/snapshots
   ```
   Note the fix stops the growth but does **not** reclaim already-accumulated
   files — delete them (or the PVC, at idle) once the fixed chart is deployed,
   and read pitfall #6 first: clearing this store has a side effect that is not
   obvious. Prefer deleting the stale files in place over deleting the PVC. Use
   `find -delete`, NOT a shell glob — a tenant carrying tens of thousands of
   files blows past `ARG_MAX` and `rm dump-20*.dfs` fails outright:
   ```bash
   kubectl -n <ns> exec redis-queue-0 -c dragonfly -- \
     find /dragonfly/snapshots -maxdepth 1 -name 'dump-20*.dfs' -delete
   ```
   Only run that once the pod is on the fixed chart and has written its own
   `dump-summary.dfs` — otherwise it deletes the only restore point. Beyond
   reclaiming space this matters for correctness: every start logs `Load
   snapshot: Searching for snapshot in directory`, and leaving ~32k stale
   candidates in that search is a restore-the-wrong-queue risk.
3. **`--shard_round_robin_prefix` is deprecated** (Dragonfly v1.39: "deprecated and
   will be removed"). Don't add it; default hash sharding is fine.
4. **`ceph-block-r1` is size-1** (no storage replication) — durability is the snapshot
   itself. Acceptable; use `ceph-block` (3×) only if you want belt-and-suspenders.
5. **RollingUpdate→Recreate is patchable** (a normal apply handles it); the tkf stg
   "stuck sync" was actually pitfall #1, not the strategy change. No `Replace=true`
   annotation needed.
6. **Wiping this store also wipes the sidekiq-cron schedule — restart the worker.**
   `sidekiq-cron` keeps its registry *in Redis* (`cron_jobs:<queue>`,
   `cron_job:<queue>:<name>`), and the chart registers it only from
   `Sidekiq.configure_server` at worker **startup**. So deleting the PVC (or
   `FLUSHDB`) silently unschedules every recurring job, and the worker will not
   re-register on its own: it just reconnects ("Redis is online, N sec downtime")
   and carries on with nothing to enqueue. Nothing alerts on this — the worker is
   Ready, the queue is healthy, and the jobs simply never run.
   Hit on `aypex-tech-stg` 2026-09-10: clearing the full PVC stopped
   `Spree::StockReservations::ExpireJob`, which Spree 5.5+ needs ~every minute or
   expired holds accumulate and keep suppressing available stock.
   After any destructive action on the queue store:
   ```bash
   kubectl -n <ns> rollout restart deploy/worker
   kubectl -n <ns> exec redis-queue-0 -c dragonfly -- redis-cli -p 9999 -n 0 --scan | grep cron_job
   ```
   Checking the job queues are idle (the cutover advice below) is necessary but
   NOT sufficient — `queue:*`, `schedule`, `retry` and `dead` can all read zero
   while the cron registry is exactly what you are about to destroy.
   A *routine* pod roll is safe: the snapshot reloads the registry, which is
   precisely what the persistence in Part 1 buys you. Only wiping the volume
   loses it.

### Verify — the pod-delete survival test
Graceful delete = SIGTERM → snapshot-on-shutdown → new pod reloads from the PVC.
```bash
NS=<ns>; SEL='app.kubernetes.io/component=redis-queue'
POD=$(kubectl -n $NS get pod -l $SEL -o jsonpath='{.items[0].metadata.name}')
# baseline + seed a namespaced sentinel (won't touch real queues)
kubectl -n $NS exec $POD -- redis-cli SET survival:marker "test-$(date +%s)"
kubectl -n $NS exec $POD -- redis-cli LPUSH queue:survival_test '{"class":"X"}'
BEFORE=$(kubectl -n $NS exec $POD -- redis-cli DBSIZE)
# restart
kubectl -n $NS delete pod $POD --wait=true
kubectl -n $NS wait --for=condition=ready pod -l $SEL --timeout=120s
NEW=$(kubectl -n $NS get pod -l $SEL -o jsonpath='{.items[0].metadata.name}')
# survived?  marker + queue len + DBSIZE must match; logs show the load
kubectl -n $NS exec $NEW -- redis-cli GET survival:marker
kubectl -n $NS exec $NEW -- redis-cli LLEN queue:survival_test
kubectl -n $NS exec $NEW -- redis-cli DBSIZE     # == $BEFORE
kubectl -n $NS logs $NEW | grep -i 'Load snapshot\|Loading /data/dump'
kubectl -n $NS exec $NEW -- redis-cli DEL survival:marker queue:survival_test   # cleanup
```

### Cutover (existing ephemeral queue → persistent)
The **first** cutover is lossy: the old pods predate `dbfilename` so they don't
snapshot on the way down. **Do it at idle** — check `sum(sidekiq_jobs_waiting_count)`
is ~0 first. Verify on staging (incl. the survival test) before prod. Every restart
*after* the first is protected.

---

## Part 2 — Sidekiq worker liveness probe

### When to use
A Sidekiq worker serves no HTTP, so the default `/up` probe must be **off** (leaving
it on crashloops the worker). That leaves no liveness signal: a *wedged* Sidekiq
(heartbeat thread deadlocked, Redis socket black-holed) sits there not draining the
queue and never restarts. A `pgrep`-style check won't catch a wedge — the process is
still alive. Use a **heartbeat-freshness** file probe instead.

### Design
- Backend touches a marker file on **every Sidekiq beat** (~10s); the probe restarts
  the pod if the marker goes stale. A stalled beat thread → stale file → restart.
- No **readiness** probe — the worker has no Service, so readiness gates nothing.

### Config
**Backend** (`config/initializers/sidekiq.rb`), server-only:
```ruby
require "fileutils"
Sidekiq.configure_server do |config|
  marker = "/tmp/sidekiq_alive"
  config.on(:startup)  { FileUtils.touch(marker) }
  config.on(:beat)     { FileUtils.touch(marker) }   # NOT :heartbeat — see pitfalls
  config.on(:shutdown) { FileUtils.rm_f(marker) }
end
```
**Chart** worker values (exec freshness check; path is the writable tmpfs emptyDir
the worker already mounts):
```yaml
worker:
  livenessProbe:  { enabled: false }   # default /up off
  readinessProbe: { enabled: false }   # no Service
  customLivenessProbe:
    exec:
      command:
        - sh
        - -c
        - 'test "$(( $(date +%s) - $(stat -c %Y /tmp/sidekiq_alive 2>/dev/null || echo 0) ))" -lt 45'
    initialDelaySeconds: 60     # Rails+Spree boot before the first :startup touch
    periodSeconds: 15
    failureThreshold: 3
```
45s ≈ 4 missed 10s beats — generous enough to avoid flapping.

### Pitfalls
1. **Use `:beat`, NOT `:heartbeat`.** In Sidekiq 8 `:heartbeat` fires **once** (first
   beat / partition repair); `:beat` fires **every 10s**. With `:heartbeat` the marker
   is created but never refreshed → goes stale → the probe crashloops the worker. The
   bug is invisible to "does the file exist?" — **verify the mtime *advances***.
2. **Ordering: ship the backend image BEFORE the chart probe** to any env. An older
   image never creates the file, so the probe has nothing to check → crashloop. With
   Kargo's bundled freight (chart + images in one Freight) they arrive together, which
   is safe because `initialDelaySeconds: 60` covers the boot window.
3. **Worker pod label is `app.kubernetes.io/name=worker`** (Bitnami-style from the
   rails-server subchart), NOT `...component=worker` (only the custom redis-* templates
   use `component`). A wrong selector returns an empty pod name and silently no-ops
   your exec checks — and can read as a false "marker missing".
4. **Workers restart ~2× on any roll — not a regression.** Sidekiq can boot before the
   redis-queue Service has a ready endpoint and die with
   `No route to host ... redis://<rel>-redis-queue:6379` (exitCode 1, ~3s), back off,
   reconnect, then run stable. Worst when the queue rolls concurrently. Confirm it
   *settles* (restart count stops rising, stays Ready **past** the 60s probe delay).

### Verify
```bash
NS=<ns>; POD=$(kubectl -n $NS get pod -l app.kubernetes.io/name=worker -o jsonpath='{.items[0].metadata.name}')
# 1) marker REFRESHES (mtime must advance ~+10s/beat) — not just exists
for n in 1 2 3; do kubectl -n $NS exec $POD -c rails-server -- stat -c %Y /tmp/sidekiq_alive; sleep 11; done
# 2) probe passes: restart count flat + Ready past the 60s initialDelay
kubectl -n $NS get pod $POD -o jsonpath='restarts={.status.containerStatuses[?(@.name=="rails-server")].restartCount} ready={.status.containerStatuses[?(@.name=="rails-server")].ready}{"\n"}'
```

---

## Promotion (Kargo)
The tkf Warehouse bundles the chart + all images into **one Freight**, so promoting
the latest verified Freight ships chart + images **together** (which satisfies the
liveness ordering rule above). prd is a manual gate:
```bash
kargo promote --project kargo-<tenant> --stage prd --freight <freight-name>
```
Pick the Freight whose `charts[].version` and `images[].tag` are the ones you verified
on stg (`kubectl -n kargo-<tenant> get freight <name> -o jsonpath=...`). Always run the
survival test on staging — and on prod at idle — before considering it done.
