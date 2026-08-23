{{/*
Target namespace: default to "{name}-{env}"; allow override via .Values.namespace.

Terraform owns the Namespace object itself (with its PSA labels and the ESO
SecretStore). This chart only ADDRESSES the namespace -- it must never create
it, and the ApplicationSet must not set CreateNamespace=true: an ArgoCD-owned
Namespace cascade-prunes every workload in it when the App is removed.
*/}}
{{- define "aypex.namespace" -}}
{{- if .Values.namespace -}}
{{ .Values.namespace }}
{{- else if .Values.env -}}
{{ .Values.name }}-{{ .Values.env }}
{{- else -}}
{{ .Release.Namespace }}
{{- end -}}
{{- end -}}

{{/*
Brand-scoped resource name. Args: (dict "ctx" . "suffix" "<suffix>")
*/}}
{{- define "aypex.resourceName" -}}
{{- printf "%s-%s" .ctx.Values.name .suffix | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels.
*/}}
{{- define "aypex.labels" -}}
app.kubernetes.io/name: aypex-tech
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: aypex-tech
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
aypex.io/brand: {{ .Values.name | quote }}
aypex.io/env: {{ .Values.env | quote }}
{{- end -}}

{{/*
ExternalSecret that extracts the whole namespace bundle and renders selected
keys through a template. Args:
  (dict "name" "<suffix>" "data" (dict "ENV_VAR" "asm_key") "context" $)

`type` is optional and used for the CNPG basic-auth secrets.
*/}}
{{- define "aypex.bundleSecret" -}}
{{- $name := include "aypex.resourceName" (dict "ctx" .context "suffix" .name) -}}
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ $name }}
  namespace: {{ include "aypex.namespace" .context }}
  labels: {{- include "aypex.labels" .context | nindent 4 }}
  annotations:
    {{- /* Ahead of everything: the CNPG Cluster will not bootstrap until the
           Secret its passwordSecret points at exists. */}}
    argocd.argoproj.io/sync-wave: "-10"
spec:
  refreshInterval: {{ .context.Values.externalSecrets.refreshInterval }}
  secretStoreRef:
    name: {{ .context.Values.externalSecrets.storeName }}
    kind: {{ .context.Values.externalSecrets.storeKind }}
  dataFrom:
    - extract:
        key: {{ .context.Values.externalSecrets.asmKeys.bundle }}
  target:
    name: {{ $name }}
    creationPolicy: Owner
    template:
      {{- with .type }}
      type: {{ . }}
      {{- end }}
      data:
        {{- range $env, $key := .data }}
        {{ $env }}: "{{ printf "{{ .%s }}" $key }}"
        {{- end }}
        {{- range $env, $literal := (.literals | default dict) }}
        {{ $env }}: {{ $literal | quote }}
        {{- end }}
{{- end -}}

{{/*
ExternalSecret mapping an IAM service-user bundle straight through, no
renaming. Args: (dict "name" "<suffix>" "asmKey" "..." "context" $)
*/}}
{{- define "aypex.iamSecret" -}}
{{- $name := include "aypex.resourceName" (dict "ctx" .context "suffix" .name) -}}
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ $name }}
  namespace: {{ include "aypex.namespace" .context }}
  labels: {{- include "aypex.labels" .context | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
spec:
  refreshInterval: {{ .context.Values.externalSecrets.refreshInterval }}
  secretStoreRef:
    name: {{ .context.Values.externalSecrets.storeName }}
    kind: {{ .context.Values.externalSecrets.storeKind }}
  target:
    name: {{ $name }}
    creationPolicy: Owner
  data:
    - secretKey: AWS_ACCESS_KEY_ID
      remoteRef:
        key: {{ .asmKey }}
        property: AWS_ACCESS_KEY_ID
    - secretKey: AWS_SECRET_ACCESS_KEY
      remoteRef:
        key: {{ .asmKey }}
        property: AWS_SECRET_ACCESS_KEY
{{- end -}}
