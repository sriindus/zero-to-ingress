{{/*
Chart name, overridable.
*/}}
{{- define "hello-world-frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. Truncated at 63 chars for the DNS label limit.
*/}}
{{- define "hello-world-frontend.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "hello-world-frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels on every object.
*/}}
{{- define "hello-world-frontend.labels" -}}
helm.sh/chart: {{ include "hello-world-frontend.chart" . }}
{{ include "hello-world-frontend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: hello-world
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Selector labels — immutable once deployed, so keep this set minimal and stable.
*/}}
{{- define "hello-world-frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hello-world-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "hello-world-frontend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hello-world-frontend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference; tag falls back to the chart's appVersion.
*/}}
{{- define "hello-world-frontend.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}
