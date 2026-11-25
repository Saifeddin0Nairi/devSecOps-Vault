# Vault Agent for Grafana: Grafana cannot talk to Vault, so the agent logs in with
# AppRole, reads secret/grafana and writes the admin password to a file for Grafana.
vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/bootstrap/role-id"
      secret_id_file_path = "/bootstrap/secret-id"
      # By default the agent deletes the secret-id file after reading it. Keep it, so the
      # agent can log in again after a restart (demo trade-off, see vault-init.sh).
      remove_secret_id_file_after_reading = false
    }
  }
}

template {
  source               = "/vault/agent/grafana-admin-password.tpl"
  destination          = "/secrets/admin-password"
  perms                = "0444"
  error_on_missing_key = true
}
