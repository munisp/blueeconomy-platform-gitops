{{- define "security-operations.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "security-operations.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "security-operations.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "security-operations.labels" -}}
app.kubernetes.io/name: {{ include "security-operations.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream | quote }}
{{- end -}}

{{- define "security-operations.selectorLabels" -}}
app.kubernetes.io/name: {{ include "security-operations.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "security-operations.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "security-operations.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "security-operations.secretName" -}}
{{- printf "%s-secrets" (include "security-operations.fullname" .) -}}
{{- end -}}

{{- /* Shared pod template for security-operations components. Expects a
       dict with keys: root ($), name (component name), component (values). */ -}}
{{- define "security-operations.podTemplate" -}}
{{- $ := .root -}}
{{- $name := .name -}}
{{- $component := .component -}}
{{- $fullName := include "security-operations.fullname" $ -}}
{{- $secretName := include "security-operations.secretName" $ -}}
metadata:
  labels:
    {{- include "security-operations.selectorLabels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $name | quote }}
    blueeconomy.platform/workstream: {{ $.Values.workstream | quote }}
  {{- if and $.Values.dapr.enabled (ne ($component.kind | default "Deployment") "CronJob") }}
  annotations:
    dapr.io/enabled: "true"
    dapr.io/app-id: {{ required (printf "%s.daprAppId is required when dapr.enabled=true" $name) $component.daprAppId | quote }}
    dapr.io/app-protocol: {{ $.Values.dapr.appProtocol | quote }}
    dapr.io/enable-metrics: "true"
    dapr.io/metrics-port: {{ $.Values.dapr.metricsPort | quote }}
  {{- end }}
spec:
  serviceAccountName: {{ include "security-operations.serviceAccountName" $ }}
  automountServiceAccountToken: false
  securityContext:
    {{- toYaml $.Values.podSecurityContext | nindent 4 }}
  {{- with $.Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  containers:
    - name: {{ $name | quote }}
      image: {{ printf "%s@%s" (required (printf "%s.image.repository is required" $name) $component.image.repository) (required (printf "%s.image.digest is required" $name) $component.image.digest) | quote }}
      imagePullPolicy: {{ $component.image.pullPolicy }}
      {{- if eq $name "detection-engine" }}
      # --rules is flag-required (cmd/detection-engine/main.go); the rule
      # document is mounted from the governance-approved ConfigMap below.
      args:
        - --rules
        - {{ printf "%s/detection-rules.yaml" $component.rules.mountPath | quote }}
      {{- end }}
      {{- if eq ($component.kind | default "Deployment") "CronJob" }}
      # Bounded generator run (cmd/opencti-bridge): --output and
      # --ruleset-version are flag-required; --strict is the prod posture.
      args:
        - --output
        - /var/lib/opencti-bridge/out
        - --ruleset-version
        - {{ required "opencti-bridge.rulesetVersion is required" $component.rulesetVersion | quote }}
        {{- if $component.strict }}
        - --strict
        {{- end }}
      {{- end }}
      {{- if and $component.service $component.service.enabled }}
      ports:
        - name: http
          containerPort: {{ $component.port }}
          protocol: TCP
      {{- end }}
      env:
        {{- range $key, $value := (default dict $component.env) }}
        - name: {{ $key | quote }}
          value: {{ $value | quote }}
        {{- end }}
        {{- range $key := (default (list) $component.secretEnv) }}
        - name: {{ $key | quote }}
          valueFrom:
            secretKeyRef:
              name: {{ $secretName | quote }}
              key: {{ $key | quote }}
        {{- end }}
        {{- if $.Values.keyDirectory.enabled }}
        - name: KEY_DIRECTORY_PATH
          value: {{ $.Values.keyDirectory.mountPath | quote }}
        {{- end }}
        {{- if and (hasKey $component "temporalEnv") $component.temporalEnv }}
        - name: {{ $component.temporalEnv.addressKey | default "TEMPORAL_ADDRESS" | quote }}
          value: {{ $.Values.temporal.address | quote }}
        - name: {{ $component.temporalEnv.namespaceKey | default "TEMPORAL_NAMESPACE" | quote }}
          value: {{ $.Values.temporal.namespace | quote }}
        {{- end }}
      resources:
        {{- toYaml $component.resources | nindent 8 }}
      securityContext:
        {{- toYaml $.Values.securityContext | nindent 8 }}
      {{- if and $component.service $component.service.enabled $component.probes }}
      startupProbe:
        httpGet:
          path: {{ $component.probes.livenessPath }}
          port: http
        failureThreshold: 30
        periodSeconds: 5
      readinessProbe:
        httpGet:
          path: {{ $component.probes.readinessPath }}
          port: http
        initialDelaySeconds: 5
        periodSeconds: 10
      livenessProbe:
        httpGet:
          path: {{ $component.probes.livenessPath }}
          port: http
        initialDelaySeconds: 15
        periodSeconds: 20
      {{- end }}
      volumeMounts:
        - name: tmp
          mountPath: /tmp
        {{- if $.Values.keyDirectory.enabled }}
        # Producer-signature key directory (charts/opa-policies): the
        # service reads KEY_DIRECTORY_PATH/key-directory.json to verify
        # envelope provenance.signature fail-closed.
        - name: producer-key-directory
          mountPath: {{ $.Values.keyDirectory.mountPath }}
          readOnly: true
        {{- end }}
        {{- if eq $name "detection-engine" }}
        - name: detection-rules
          mountPath: {{ $component.rules.mountPath }}
          readOnly: true
        {{- end }}
        {{- if eq ($component.kind | default "Deployment") "CronJob" }}
        - name: generator-output
          mountPath: /var/lib/opencti-bridge
        {{- end }}
  volumes:
    - name: tmp
      emptyDir: {}
    {{- if $.Values.keyDirectory.enabled }}
    - name: producer-key-directory
      configMap:
        name: {{ $.Values.keyDirectory.configMapName }}
    {{- end }}
    {{- if eq $name "detection-engine" }}
    - name: detection-rules
      configMap:
        name: {{ printf "%s-detection-rules" $fullName | trunc 63 | trimSuffix "-" }}
    {{- end }}
    {{- if eq ($component.kind | default "Deployment") "CronJob" }}
    - name: generator-output
      emptyDir: {}
    {{- end }}
{{- end -}}
