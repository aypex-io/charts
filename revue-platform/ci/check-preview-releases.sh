#!/usr/bin/env bash
# Two preview releases (revue-pr-1, revue-pr-2) share the revue-preview namespace,
# and their HTTPRoutes share the gateway namespace. Render both and fail if any
# object would collide, or if a preview loses its sample-data hook, renders its
# own ExternalSecrets, or routes its app host twice.
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
fail() { printf 'FAIL: %b\n' "$*" >&2; exit 1; }

render() {
  local n=$1 args=()
  for workload in web worker migrate seed sample; do
    args+=(--set "${workload}.database.host=revue-pr-${n}-db-rw")
  done
  helm template "revue-pr-${n}" . -f ci/preview-values.yaml \
    --set "cnpg.name=revue-pr-${n}-db" \
    --set "hostnames.admin=preview-${n}.revue.fyi" \
    --set "hostnames.api=preview-${n}.revue.fyi" \
    --set "hostnames.public=preview-${n}-reviews.revue.fyi" \
    --set "hostnames.marketing=preview-${n}-www.revue.fyi" \
    "${args[@]}" > "${out}/pr-${n}.yaml"
}

render 1
render 2

# (a) No kind/namespace/name collides across the two releases.
# `yq e` (per document), not `ea`: eval-all joins every object onto one line.
dups=$(yq e '[.kind, (.metadata.namespace // ""), .metadata.name] | join("/")' \
  "${out}/pr-1.yaml" "${out}/pr-2.yaml" | grep -v '^---$' | sort | uniq -d)
[ -z "$dups" ] || fail "objects collide across two preview releases:\n${dups}"

for n in 1 2; do
  f="${out}/pr-${n}.yaml"

  # (b) Exactly one Job runs revue:demo, as the weight-5 hook (after migrate -5, seed 0).
  demo_jobs=$(yq ea '[select(.kind == "Job" and ((.spec.template.spec.containers[0].command // []) | join(" ") | test("revue:demo")))] | length' "$f")
  [ "$demo_jobs" = 1 ] || fail "revue-pr-${n}: expected 1 revue:demo Job, got ${demo_jobs}"
  weight=$(yq ea 'select(.kind == "Job" and ((.spec.template.spec.containers[0].command // []) | join(" ") | test("revue:demo"))) | .metadata.annotations["helm.sh/hook-weight"]' "$f")
  [ "$weight" = 5 ] || fail "revue-pr-${n}: revue:demo hook weight is '${weight}', want 5"

  # (c) No per-release ExternalSecrets: previews share revue-preview-shared's.
  es=$(yq ea '[select(.kind == "ExternalSecret")] | length' "$f")
  [ "$es" = 0 ] || fail "revue-pr-${n}: renders ${es} ExternalSecrets, want 0"

  # (d) The app host (admin == api) is routed exactly once.
  routes=$(yq ea "[select(.kind == \"HTTPRoute\" and (.spec.hostnames[] == \"preview-${n}.revue.fyi\"))] | length" "$f")
  [ "$routes" = 1 ] || fail "revue-pr-${n}: preview-${n}.revue.fyi is routed ${routes} times, want 1"
done

echo "OK: two preview releases render without collisions"
