{{/*
Target namespace: default to "revue-{env}"; allow override via .Values.namespace.
*/}}
{{- define "revue.namespace" -}}
{{- if .Values.namespace -}}
{{ .Values.namespace }}
{{- else if .Values.env -}}
{{ .Values.name }}-{{ .Values.env }}
{{- else -}}
{{ .Release.Namespace }}
{{- end -}}
{{- end -}}

{{/*
Build a product-scoped resource name. Args: (dict "ctx" . "suffix" "<suffix>")
*/}}
{{- define "revue.resourceName" -}}
{{- printf "%s-%s" .ctx.Values.name .suffix | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels.
*/}}
{{- define "revue.labels" -}}
app.kubernetes.io/name: revue
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: revue
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
revue.aypex.io/env: {{ .Values.env | quote }}
{{- end -}}
