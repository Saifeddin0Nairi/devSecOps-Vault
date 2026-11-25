# Policy "democyber": the app can read its own secret, and nothing else.
# KV v2 stores the values under secret/data/<name>.
path "secret/data/democyber" {
  capabilities = ["read"]
}
