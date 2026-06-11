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
