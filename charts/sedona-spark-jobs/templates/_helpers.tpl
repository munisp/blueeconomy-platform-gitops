{{/*
Merged Spark conf: the operator-supplied spark.sparkConf map plus the
opt-in observability wiring (default OFF, render-gated in
000-validation.yaml).

Honest coverage notes (W-OTEL follow-up):
- observability.prometheus enables the Spark metrics system's Prometheus
  servlet sink on the Spark UI (JMX source: DAGScheduler, BlockManager,
  executor JVM gauges). Sedona geometry metrics exist only if the job
  code registers them.
- observability.otel.javaagent attaches the OTel Java agent to the
  driver/executor JVMs. It auto-instruments supported JVM libraries
  (HTTP/gRPC/JDBC clients) and emits JVM runtime metrics; it does NOT
  trace Spark's scheduler/stages (no Spark instrumentation module
  exists) and it does NOT trace the PySpark Python worker or Sedona
  geometry UDFs — job-level spans remain the Python-side spans wrapping
  the job submission (W-OTEL data-platform wave).
*/}}
{{- define "sedona-spark-jobs.sparkConf" -}}
{{- $sparkConf := merge (dict) (default dict .Values.spark.sparkConf) -}}
{{- if .Values.observability.prometheus.enabled -}}
{{- $_ := set $sparkConf "spark.ui.prometheus.enabled" "true" -}}
{{- $_ := set $sparkConf "spark.metrics.conf.*.sink.prometheusServlet.class" "org.apache.spark.metrics.sink.PrometheusServlet" -}}
{{- $_ := set $sparkConf "spark.metrics.conf.*.sink.prometheusServlet.path" "/metrics/prometheus" -}}
{{- $_ := set $sparkConf "spark.metrics.conf.master.sink.prometheusServlet.path" "/metrics/master/prometheus" -}}
{{- $_ := set $sparkConf "spark.metrics.conf.applications.sink.prometheusServlet.path" "/metrics/executors/prometheus" -}}
{{- end -}}
{{- if .Values.observability.otel.javaagent.enabled -}}
{{- $_ := set $sparkConf "spark.driver.extraJavaOptions" (printf "-javaagent:%s" .Values.observability.otel.javaagent.agentPath) -}}
{{- $_ := set $sparkConf "spark.executor.extraJavaOptions" (printf "-javaagent:%s" .Values.observability.otel.javaagent.agentPath) -}}
{{- $_ := set $sparkConf "spark.kubernetes.driverEnv.OTEL_EXPORTER_OTLP_ENDPOINT" .Values.observability.otel.javaagent.otlpEndpoint -}}
{{- $_ := set $sparkConf "spark.kubernetes.executorEnv.OTEL_EXPORTER_OTLP_ENDPOINT" .Values.observability.otel.javaagent.otlpEndpoint -}}
{{- $_ := set $sparkConf "spark.kubernetes.driverEnv.OTEL_SERVICE_NAME" (printf "sedona-%s" .Values.job.name) -}}
{{- $_ := set $sparkConf "spark.kubernetes.executorEnv.OTEL_SERVICE_NAME" (printf "sedona-%s" .Values.job.name) -}}
{{- end -}}
{{- toYaml $sparkConf -}}
{{- end -}}
