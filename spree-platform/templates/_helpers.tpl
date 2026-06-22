{{/*
Resolve the target namespace for this release.
Default to `{customer.slug}-{env}`; allow override via .Values.namespace.
*/}}
{{- define "spree-store.namespace" -}}
{{- if .Values.namespace -}}
{{ .Values.namespace }}
{{- else if and .Values.customer.slug .Values.env -}}
{{ .Values.customer.slug }}-{{ .Values.env }}
{{- else -}}
{{ .Release.Namespace }}
{{- end -}}
{{- end -}}

{{/*
Build a customer-scoped resource name.
Used for secrets + CNPG cluster names so xtrnutrition's resources don't
collide with tkf's if they share a namespace (they don't, but the prefix
keeps things grep-able and makes the customer obvious from any get-all).
Args: (dict "ctx" . "suffix" "<suffix>")
*/}}
{{- define "spree-store.resourceName" -}}
{{- printf "%s-%s" .ctx.Values.customer.slug .suffix | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for resources owned by the umbrella.
*/}}
{{- define "spree-store.labels" -}}
app.kubernetes.io/name: spree-store
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: spree-store
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
spree-store.aypex.io/customer: {{ .Values.customer.slug | quote }}
spree-store.aypex.io/env: {{ .Values.env | quote }}
{{- end -}}

{{/*
Service name for a given subchart alias. Mirrors the rails/nextjs chart's
common.names.fullname output: `<release>-<chartname>`.
*/}}
{{- define "spree-store.subchartFullname" -}}
{{- $release := .ctx.Release.Name -}}
{{- $name := .alias -}}
{{- printf "%s-%s" $release ($name | lower) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Security context for the staging-refresh CNPG-operand phases (uid 26).
*/}}
{{- define "spree-store.refreshPgSecurity" -}}
runAsNonRoot: true
runAsUser: 26
runAsGroup: 26
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false
capabilities:
  drop: [ALL]
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Security context for the staging-refresh Rails/Payload phases (uid 1000).
readOnlyRootFilesystem is relaxed — the throwaway job runs migrate/seed which
write Rails tmp; the pod is short-lived and holds no secrets on disk.
*/}}
{{- define "spree-store.refreshRailsSecurity" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false
capabilities:
  drop: [ALL]
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Env for the staging-refresh Rails phases: DATABASE_URL pinned at the in-pod
Postgres (local trust auth — no password) plus the overlay-supplied railsEnv
(SMTP_FROM_ADDRESS for the prod boot-guard, REDIS_URL for the Sidekiq clear,
STORE_URL / RAILS_HOST / TKF_ALLOW_SANITIZE / STAGING_SPREE_PUBLISHABLE_KEY for
the sanitize task). Args: (dict "ctx" $ "db" "spree")
*/}}
{{- define "spree-store.refreshRailsEnv" -}}
- name: DATABASE_URL
  value: "postgresql://{{ .db }}@127.0.0.1:5432/{{ .db }}"
{{- with .ctx.Values.jobs.stagingRefresh.railsEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Common ExternalSecret skeleton: define once, reuse via fromYaml.
Args: (dict "name" "..." "asmKey" "..." "data" (list "FIELD" ...) "context" $)
*/}}
{{- define "spree-store.externalSecret" -}}
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .name }}
  namespace: {{ include "spree-store.namespace" .context }}
  labels: {{- include "spree-store.labels" .context | nindent 4 }}
spec:
  refreshInterval: {{ .context.Values.externalSecrets.refreshInterval }}
  secretStoreRef:
    name: {{ .context.Values.externalSecrets.storeName }}
    kind: {{ .context.Values.externalSecrets.storeKind }}
  target:
    name: {{ .name }}
    creationPolicy: Owner
  data:
    {{- range .data }}
    - secretKey: {{ . }}
      remoteRef:
        key: {{ $.asmKey }}
        property: {{ . }}
    {{- end }}
{{- end -}}
