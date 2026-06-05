{{/*
Return the ServiceAccount name. Bitnami common does not ship this helper.
*/}}
{{- define "rails.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the assembled DATABASE_URL value from database.* values.
Used as an env var when database.enabled is true and database.urlOverride is empty.
*/}}
{{- define "rails.databaseUrl" -}}
{{- if .Values.database.urlOverride -}}
{{ .Values.database.urlOverride }}
{{- else -}}
postgresql://$(DATABASE_USER):$(DATABASE_PASSWORD)@{{ .Values.database.host }}:{{ .Values.database.port }}/{{ .Values.database.name }}
{{- end -}}
{{- end -}}

{{/*
Render the standard env block: database wiring (if enabled), extraEnvVars,
and any sidekick configuration. Used by deployment.yaml.
*/}}
{{- define "rails.env" -}}
{{- if and .Values.database.enabled (not .Values.database.urlOverride) }}
- name: DATABASE_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.userSecretRef }}
      key: username
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.userSecretRef }}
      key: password
{{- end }}
{{- if .Values.database.enabled }}
- name: {{ .Values.database.envVar }}
  value: {{ include "rails.databaseUrl" . | quote }}
{{- end }}
{{- if .Values.extraEnvVars }}
{{ include "common.tplvalues.render" (dict "value" .Values.extraEnvVars "context" $) }}
{{- end }}
{{- end -}}

{{/*
Render the standard envFrom block.
*/}}
{{- define "rails.envFrom" -}}
{{- if .Values.configmap.create }}
- configMapRef:
    name: {{ include "common.names.fullname" . }}
{{- end }}
{{- if .Values.extraEnvVarsCM }}
- configMapRef:
    name: {{ .Values.extraEnvVarsCM }}
{{- end }}
{{- if .Values.extraEnvVarsSecret }}
- secretRef:
    name: {{ .Values.extraEnvVarsSecret }}
{{- end }}
{{- end -}}
