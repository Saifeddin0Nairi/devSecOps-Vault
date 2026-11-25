# Policy "grafana": Grafana's Vault Agent can read Grafana's secret, and nothing else.
path "secret/data/grafana" {
  capabilities = ["read"]
}
