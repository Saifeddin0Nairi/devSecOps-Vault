#!/bin/sh
# Vault integration test (CI step 7, and local).
# It starts vault, vault-init and democyber with an image that already exists (it never
# builds one), then checks:
#   1. the API key comes from Vault: GET /api/secure answers 401 without a key,
#      401 with a wrong key and 200 with the key read from Vault
#   2. least privilege: with the deny policy, the restarted app stops (it never becomes
#      healthy) and its log says "permission denied" (fail closed)
#   3. recovery: with the normal policy back, the app is healthy again and accepts the key
# The stack is always removed at the end (docker compose down -v), even after a failure.
#
# Usage:     scripts/test-vault-integration.sh   (from the project root, with a .env file)
# Image:     DEMOCYBER_IMAGE (default: democyber-vault:local). In CI: the image that was
#            built, smoke-tested and scanned in the steps before.
# Exit code: 0 = every check passed, 1 = a check failed.
#
# No "set -e": every check is explicit, and a failed check goes through fail().
set -u

export DEMOCYBER_IMAGE="${DEMOCYBER_IMAGE:-democyber-vault:local}"
base_url="http://127.0.0.1:8080"

step() { printf '\n== %s\n' "$*"; }
ok() { printf 'ok   %s\n' "$*"; }

# Last log lines, for debugging, with every possible copy of the API key removed:
# the lines that hold the key itself (once it is known) are dropped, and any 64-character
# hex value (the format of the key Vault generates) is hidden. This also protects a failure
# that happens before the key is read, and local runs, where GitHub cannot mask anything.
print_logs() {
  echo "--- last lines of the vault-init and democyber logs (secrets hidden):"
  docker compose logs --no-color --tail 25 vault-init democyber 2>&1 \
    | { if [ -n "${key:-}" ]; then grep -vF -- "$key"; else cat; fi; } \
    | sed -E 's/[0-9a-fA-F]{64}/[hidden]/g'
}

fail() {
  printf '\nVAULT INTEGRATION TEST FAILED: %s\n' "$*"
  print_logs
  exit 1
}

cleanup() {
  step "cleanup: docker compose down -v"
  if docker compose down -v --remove-orphans > /dev/null 2>&1; then
    echo "stack removed"
  else
    echo "WARNING: docker compose down -v failed"
  fi
}

# Health of a container: healthy, unhealthy, starting (or empty if it does not exist)
health_of() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$1" 2> /dev/null
}

# HTTP status of GET /api/secure. Extra curl options (a header) come first.
status() {
  curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$@" "$base_url/api/secure"
}

# Same, with the key from Vault. curl reads the header from stdin (-H @-), so the key
# never appears in a command line (no "ps" or /proc leak on the runner).
status_with_key() {
  printf 'X-API-Key: %s\n' "$key" | status -H @-
}

expect() { # expect <wanted> <got> <description>
  if [ "$2" = "$1" ]; then
    ok "$3 -> $2"
  else
    fail "$3: expected $1, got $2"
  fi
}

# Replace the policy "democyber" with a file mounted in the vault container.
# MSYS_NO_PATHCONV=1: Git Bash on Windows must not turn /vault/... into a Windows path.
write_policy() {
  MSYS_NO_PATHCONV=1 docker compose exec -T vault \
    vault policy write democyber "/vault/policies/$1" > /dev/null
}

# --- Before starting -------------------------------------------------------------------
if [ ! -f .env ]; then
  echo "VAULT INTEGRATION TEST FAILED: no .env file (README section 7 shows how to create it)"
  exit 1
fi
if ! docker image inspect "$DEMOCYBER_IMAGE" > /dev/null 2>&1; then
  echo "VAULT INTEGRATION TEST FAILED: image $DEMOCYBER_IMAGE not found (this test never builds)"
  exit 1
fi

step "start vault, vault-init and democyber (image $DEMOCYBER_IMAGE, no build)"
docker compose down -v --remove-orphans > /dev/null 2>&1 # start from a clean state
trap cleanup EXIT
trap 'exit 1' INT TERM

# Starting democyber also starts what it depends on: vault, then vault-init
docker compose up -d --no-build --wait --wait-timeout 180 democyber \
  || fail "democyber did not become healthy with Vault"

init_id=$(docker compose ps -aq vault-init)
init_state=$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$init_id" 2> /dev/null)
[ "$init_state" = "exited 0" ] || fail "vault-init did not end with exit code 0 (state: $init_state)"
ok "vault-init ended with exit code 0"

app_id=$(docker compose ps -q democyber)
[ "$(health_of "$app_id")" = "healthy" ] || fail "democyber is not healthy"
ok "democyber is healthy"

# --- 1. The API key comes from Vault -----------------------------------------------------
step "1. the API key comes from Vault"
key=$(docker compose exec -T vault vault kv get -field=api-key secret/democyber) \
  || fail "cannot read secret/democyber from Vault"
key=$(printf '%s' "$key" | tr -d '\r\n')
[ -n "$key" ] || fail "the API key in Vault is empty"
# GitHub Actions: hide the value in the job log from now on (it is never printed anyway)
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  echo "::add-mask::$key"
fi
ok "API key read from Vault (never printed)"

expect 401 "$(status)" "GET /api/secure without a key"
expect 401 "$(status -H 'X-API-Key: wrong-key')" "GET /api/secure with a wrong key"
expect 200 "$(status_with_key)" "GET /api/secure with the key from Vault"

if docker compose logs --no-color democyber 2>&1 | grep -qF -- "$key"; then
  fail "the API key appears in the app log"
fi
ok "the API key is not in the app log"

# --- 2. Least privilege: no access, no start ---------------------------------------------
step "2. least privilege: deny policy, then restart the app"
write_policy democyber-deny.hcl || fail "cannot write the deny policy"
ok "policy democyber now denies secret/data/democyber"
docker compose restart democyber > /dev/null 2>&1 || fail "cannot restart democyber"

denied=no
running=true
tries=0
while [ "$tries" -lt 30 ]; do # at most about 60 seconds
  [ "$(health_of "$app_id")" = "healthy" ] \
    && fail "the app became healthy although Vault denies access"
  if docker compose logs --no-color democyber 2>&1 | grep -q 'permission denied'; then
    denied=yes
  fi
  running=$(docker inspect -f '{{.State.Running}}' "$app_id" 2> /dev/null)
  [ "$denied" = yes ] && [ "$running" = false ] && break
  tries=$((tries + 1))
  sleep 2
done
[ "$denied" = yes ] || fail "no \"permission denied\" in the app log"
[ "$running" = false ] || fail "the app is still running although Vault denies access"
exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$app_id")
ok "the app stopped (exit code $exit_code) and never became healthy"
ok "its log says \"permission denied\""

# --- 3. Recovery ---------------------------------------------------------------------------
step "3. recovery: normal policy back, then start the app again"
write_policy democyber.hcl || fail "cannot restore the democyber policy"
ok "policy democyber restored (read only on secret/data/democyber)"
docker compose up -d --no-build --no-deps --wait --wait-timeout 120 democyber \
  || fail "the app did not become healthy again"
app_id=$(docker compose ps -q democyber)
[ "$(health_of "$app_id")" = "healthy" ] || fail "democyber is not healthy"
ok "democyber is healthy again"
expect 200 "$(status_with_key)" "GET /api/secure with the key from Vault"

printf '\nVAULT INTEGRATION TEST PASSED\n'
exit 0
