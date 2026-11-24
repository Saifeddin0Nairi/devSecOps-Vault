#!/bin/sh
# Smoke test for the democyber container (CI and local).
# It passes when, before the timeout:
#   - the container is healthy (Actuator health on port 8081 is UP),
#   - GET /             answers 200,
#   - GET /api/secure   answers 401 without a key,
#   - GET /actuator/health answers 404 on the public port (Actuator is not exposed there).
#
# Usage:     scripts/smoke-test.sh <container> [base-url] [timeout-seconds]
# Exit code: 0 = every check passed, 1 = still failing at the timeout.
#
# No "set -e": failed requests are normal while the app starts. The loop decides.
set -u

container="${1:?usage: scripts/smoke-test.sh <container> [base-url] [timeout-seconds]}"
base_url="${2:-http://127.0.0.1:8080}"
timeout="${3:-90}"
pause=3

# HTTP status code of a GET request. curl prints 000 when nothing answers.
http_code() {
  curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$1"
}

try=0
while :; do
  try=$((try + 1))
  health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container" 2>/dev/null)
  [ -n "$health" ] || health="no-container"
  root=$(http_code "$base_url/")
  secure=$(http_code "$base_url/api/secure")
  actuator=$(http_code "$base_url/actuator/health")
  echo "try $try: health=$health | GET / = $root | GET /api/secure (no key) = $secure | GET /actuator/health on public port = $actuator"

  if [ "$health" = "healthy" ] && [ "$root" = "200" ] && [ "$secure" = "401" ] && [ "$actuator" = "404" ]; then
    echo "SMOKE TEST PASSED"
    exit 0
  fi
  if [ $((try * pause)) -ge "$timeout" ]; then
    echo "SMOKE TEST FAILED: still failing after ${timeout}s" >&2
    exit 1
  fi
  sleep "$pause"
done
