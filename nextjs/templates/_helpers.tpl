{{/*
Return the ServiceAccount name. Bitnami common does not ship this helper.
*/}}
{{- define "nextjs.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Render the standard env block: extraEnvVars only (no DB wiring in nextjs).
*/}}
{{- define "nextjs.env" -}}
{{- if .Values.extraEnvVars }}
{{ include "common.tplvalues.render" (dict "value" .Values.extraEnvVars "context" $) }}
{{- end }}
{{- end -}}

{{/*
Render the standard envFrom block.
*/}}
{{- define "nextjs.envFrom" -}}
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
