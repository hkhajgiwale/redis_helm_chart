{{/*
Expand the name of the chart.
*/}}
{{- define "redis.name" -}}
{{ .Chart.Name }}
{{- end -}}

{{/*
Return the name of the chart with the release name as a prefix.
*/}}
{{- define "redis.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "redis.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return the common labels used throughout the chart.
*/}}
{{- define "redis.labels" -}}
helm.sh/chart: {{ include "redis.name" . }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "redis.selectorLabels" . }}
{{- end -}}

{{/*
Return the labels for the Redis pod selector.
*/}}
{{- define "redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
