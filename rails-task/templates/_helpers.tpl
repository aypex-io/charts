{{/*
Return the ServiceAccount name. Bitnami common does not ship this helper.
*/}}
{{- define "rails-task.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the assembled DATABASE_URL value from database.* values.
*/}}
{{- define "rails-task.databaseUrl" -}}
{{- if .Values.database.urlOverride -}}
{{ .Values.database.urlOverride }}
{{- else -}}
postgresql://$(DATABASE_USER):$(DATABASE_PASSWORD)@{{ .Values.database.host }}:{{ .Values.database.port }}/{{ .Values.database.name }}
{{- end -}}
{{- end -}}

{{/*
Render the standard env block: database wiring (if enabled), extraEnvVars.
*/}}
{{- define "rails-task.env" -}}
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
  value: {{ include "rails-task.databaseUrl" . | quote }}
{{- end }}
{{- if .Values.extraEnvVars }}
{{ include "common.tplvalues.render" (dict "value" .Values.extraEnvVars "context" $) }}
{{- end }}
{{- end -}}

{{/*
Render the standard envFrom block.
*/}}
{{- define "rails-task.envFrom" -}}
{{- if .Values.extraEnvVarsCM }}
- configMapRef:
    name: {{ .Values.extraEnvVarsCM }}
{{- end }}
{{- if .Values.extraEnvVarsSecret }}
- secretRef:
    name: {{ .Values.extraEnvVarsSecret }}
{{- end }}
{{- end -}}

{{/*
Compute the Job name. When a Helm hook is set, suffix with a content hash so
each release cycle creates a distinct tracked resource (ArgoCD tracks named
hooks; a stable name would leave them perpetually "Synced" — see
feedback_argocd_helm_hooks_no_drift).
*/}}
{{- define "rails-task.jobName" -}}
{{- $base := include "common.names.fullname" . -}}
{{- if .Values.hook -}}
{{- $hash := (printf "%v-%v" .Values.command .Values.image.tag) | sha256sum | trunc 8 -}}
{{- printf "%s-%s" $base $hash | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{ $base }}
{{- end -}}
{{- end -}}
