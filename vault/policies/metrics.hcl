# Policy "metrics": Prometheus can read Vault's metrics, and nothing else.
path "sys/metrics" {
  capabilities = ["read"]
}
