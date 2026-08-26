ui = true
cluster_name = "blueeconomy-external-secrets"

storage "file" {
  path = "/openbao/data"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
disable_mlock = true

telemetry {
  unauthenticated_metrics_access = false
}
