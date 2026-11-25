# Demo 2 only (README section 8): written under the name "democyber" to replace the real
# policy. Access to the app's secret is refused, so the app must not start (fail closed).
path "secret/data/democyber" {
  capabilities = ["deny"]
}
