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

extraEnvVars IS part of the hash, and must stay that way. It used to hash only
command + image.tag, which meant a values-only change left the Job name
unchanged — so ArgoCD saw a Job of that name already present and, with
ApplyOutOfSyncOnly=true, did nothing. A FAILED hook Job therefore stayed failed
forever and the task silently never re-ran.

That bit on 2026-08-22: the tkf-prd Typesense cutover renamed the search Service
(typesense -> typesense-svc), which is a values-only change. The reindex hook had
already been created carrying the OLD TYPESENSE_URL, failed against the
now-deleted Service, and was never recreated when the corrected URL landed —
leaving prd with a healthy Typesense cluster and ZERO indexed documents until the
sync was forced by hand. No backoffLimit could have fixed that: the Job was
permanently poisoned with an address that no longer resolved.

Do NOT put anything render-unstable in this hash, or the Job re-fires on every
sync. extraEnvVars is static values-file content, so it is safe.
*/}}
{{- define "rails-task.jobName" -}}
{{- $base := include "common.names.fullname" . -}}
{{- if .Values.hook -}}
{{- $hash := (printf "%v-%v-%v" .Values.command .Values.image.tag .Values.extraEnvVars) | sha256sum | trunc 8 -}}
{{- printf "%s-%s" $base $hash | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{ $base }}
{{- end -}}
{{- end -}}
