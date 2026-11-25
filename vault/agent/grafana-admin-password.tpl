{{- with secret "secret/data/grafana" -}}{{ index .Data.data "admin-password" }}{{- end -}}
