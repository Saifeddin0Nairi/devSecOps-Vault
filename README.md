# Democyber Vault 🔐

> DevSecOps mini-project: the full TP1 → TP4 chain, plus one signature.
> **No secret in Git, in the image or in the Compose file. Every runtime secret lives in HashiCorp Vault.**

[![CI/CD](https://github.com/Saifeddin0Nairi/devSecOps-Vault/actions/workflows/ci.yml/badge.svg)](https://github.com/Saifeddin0Nairi/devSecOps-Vault/actions/workflows/ci.yml)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=Saifeddin0Nairi_devSecOps-Vault&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=Saifeddin0Nairi_devSecOps-Vault)

| | |
|---|---|
| **Author** | Saif Eddin Nairi, 5th year Cybersecurity Engineering, EPI Digital School (Sousse) |
| **Course** | DevSecOps, Mme Amara Balkis, 2026–2027 |
| **Built on** | my TP repository [`tp-devsecops`](https://github.com/Saifeddin0Nairi/tp-devsecops) (TP1 to TP4) |

---

## 1. The idea

In TP1 to TP4, I built a pipeline for the Spring Boot app `democyber`. Each TP also showed a weakness. This project does two things:

1. **Base**: it fixes every weakness found in my TP work (see [section 4](#4-what-changed-compared-to-the-tps)).
2. **Signature**: it adds **HashiCorp Vault**. The app and Grafana get their secrets from Vault at startup. Vault generates the values itself, and they are never written in the repository.

> *Gitleaks finds secrets in the code. Vault is where secrets should live.*

## 2. Tools: one row per TP

| TP | Tools | Role in this project |
|---|---|---|
| TP1 | Git, Maven, Docker, Docker Hub, GitHub Actions | version, build, test, package, publish |
| TP2 | Gitleaks, Trivy | block leaked secrets, block vulnerable images |
| TP3 | SonarCloud | code analysis and Quality Gate |
| TP4 | Actuator, Prometheus, Grafana | metrics and dashboards |
| ⭐ Bonus | HashiCorp Vault (KV v2, AppRole, Vault Agent, audit log) | stores and delivers every runtime secret |

## 3. Architecture

```mermaid
flowchart LR
    dev([Developer]) -->|push / pull request| gh[GitHub]
    gh --> s1

    subgraph ci [GitHub Actions: one job]
        direction LR
        s1[Gitleaks] --> s2[Maven build + tests] --> s3[SonarCloud] --> s4[Docker build] --> s5[Smoke test] --> s6[Trivy] --> s7[Vault test] --> s8[Publish]
    end

    s8 -->|main only| hub[(Docker Hub)]

    subgraph rt [Docker Compose: local runtime]
        direction TB
        vinit[vault-init] -->|secrets, policies, AppRoles| vault[(Vault)]
        app[democyber] -->|login + read| vault
        agent[Vault Agent] -->|login + read| vault
        agent -->|password file| graf[Grafana]
        prom[Prometheus] -->|scrape| app
        prom -->|scrape| vault
        graf -->|PromQL| prom
    end

    hub -.->|docker pull| app
```

- **CI side**: the pipeline secrets (Docker Hub and SonarCloud tokens) stay in GitHub Secrets.
- **Runtime side**: the app secrets (API key, Grafana admin password) come from Vault.

## 4. What changed compared to the TPs

| Found in | Weakness | Fix in this project |
|---|---|---|
| TP2 pipeline | The smoke test could never fail (`curl … \|\| echo`) | Real smoke test with retries. It fails the job |
| TP2 pipeline | A pull request could publish `latest` to Docker Hub | Publish only on a push to `main` |
| TP2 pipeline | Only the `latest` tag | Tags `:<commit-sha>` and `:latest` |
| TP1 to TP3 | Default token permissions | Least-privilege `permissions:` |
| TP3 (SonarCloud) | The container ran as root (Security rating B) | Non-root user |
| TP1 | No tests | Web tests run in CI |
| TP1 | Java 17 in `pom.xml`, Java 21 in CI and in the image | Java 21 everywhere |
| TP4 report | Grafana `admin/admin` | Password generated and delivered by Vault |
| TP4 report | Images on `latest` | Pinned versions |
| TP4 report | Ports open on `0.0.0.0` | Bound to `127.0.0.1` |
| TP4 report | Actuator on the public port | Separate management port `8081`, not published |
| TP2 report | "Store secrets in a vault, e.g. HashiCorp Vault" | Done |

## 5. CI/CD pipeline

One job, like in the TPs: [`.github/workflows/ci.yml`](.github/workflows/ci.yml). It runs on every push and pull request to `main`.

| # | Step | Tool | Blocks the pipeline when… | Evidence |
|---|---|---|---|---|
| 1 | Secret scan | Gitleaks | a secret is found in the pushed commits | `gitleaks-report` artifact (SARIF) |
| 2 | Build + tests | Maven | the code does not compile or a test fails | test results in the log |
| 3 | Code analysis | SonarCloud | the Quality Gate fails | SonarCloud dashboard |
| 4 | Image build | Docker | the build fails | image `democyber-vault:ci-<sha>` |
| 5 | Smoke test | curl | health is not UP, `/` is not 200, `/api/secure` without a key is not 401, or Actuator answers on the public port | job log |
| 6 | Image scan | Trivy | a HIGH or CRITICAL vulnerability is found | `trivy-report` artifact (JSON) |
| 7 | Vault integration test | Docker Compose + Vault | the app does not get its secret from Vault, the key shows up in its log, or the app still starts when Vault denies access | job log |
| 8 | Publish | Docker Hub | (runs only on a push to `main`) | `saifeddinenairi/democyber-vault:<sha>` and `:latest` |

Rules:

- Pull requests run steps 1 to 7 and never publish.
- The image tested in steps 5 to 7 is the exact image that is published.
- Third-party actions are pinned by commit SHA.
- Commits follow the TP convention: `feat:`, `fix:`, `test:`, `chore:`, `docs:`.

## 6. Vault: the signature

### 6.1 Vault in one minute

| Word | Meaning here |
|---|---|
| **Vault** | A safe for secrets, with access rules and an audit log |
| **KV v2** | A key/value secrets engine with versions: `secret/democyber`, `secret/grafana` |
| **Policy** | What a client may read. Each client can read one path only, read-only |
| **AppRole** | Login for machines: `role-id` is like a username, `secret-id` is like a password |
| **Token** | What a client receives after login. It has a short life (TTL) |
| **Vault Agent** | A helper that logs in and writes a secret to a file, for apps that don't talk to Vault (Grafana) |
| **Audit log** | One line per request: who, when, which path. Secret values are hashed |
| **Dev mode** | In-memory Vault, already unsealed, with a root token. For demos only |

### 6.2 Who reads what

| Client | Login | Can read | How it receives the secret |
|---|---|---|---|
| `democyber` | AppRole `democyber` | `secret/data/democyber` | Spring Cloud Vault at startup. No access means no start (fail closed) |
| Grafana | AppRole `grafana`, through Vault Agent | `secret/data/grafana` | Vault Agent writes a file, read with `GF_SECURITY_ADMIN_PASSWORD__FILE` |
| Prometheus | token with the `metrics` policy | `sys/metrics` | bearer token file |
| Admin (me) | root token from `.env`, dev mode only | everything | `vault` CLI and web UI |

`vault-init` is a one-shot container. At each start it creates the secrets (random values generated by Vault), the policies, the AppRoles and the audit log. Then it gives each client its login through a private volume that only this client can read. It runs as root with one Linux capability only (`CHOWN`), so that each login file belongs to the user of its client. The app gets its two login files through a 3-line wrapper in `compose.yml`, which passes them to the Java process only. Vault Agent deletes the old Grafana password file before it starts (volumes survive `docker compose down`), so Grafana always waits for the current password.

### 6.3 Where the secrets are not

- **Not in Git**: Gitleaks is green.
- **Not in the image**: `.dockerignore` sends only the JAR to the build.
- **Not in `compose.yml` or `docker inspect`**: containers receive file paths, not values.
- **Not in the logs**: the app, `vault-init` and Vault Agent never print a secret value. Only Vault itself, in dev mode, prints its own root token when it starts (see [section 13](#13-limits-and-next-steps)).
- `.env` holds one value only, the Vault dev root token. It is git-ignored (see the limits in [section 13](#13-limits-and-next-steps)).

### 6.4 Honest limit: "secret zero"

The app still needs one credential to log in to Vault: its AppRole `secret-id`. Here the trusted `vault-init` container delivers it through a private volume. In production, this is solved with a platform identity (Kubernetes auth, cloud IAM) or with a wrapped, single-use `secret-id`.

## 7. Quick start (Windows PowerShell)

Requirements: Docker Desktop (running), JDK 21, Git.

```powershell
git clone https://github.com/Saifeddin0Nairi/devSecOps-Vault.git
cd devSecOps-Vault

# 1. Local config: only the Vault dev root token, with a random value
Copy-Item .env.example .env
(Get-Content .env) -replace 'change-me', ([guid]::NewGuid().ToString()) | Set-Content .env

# 2. Build the JAR, then start everything
.\mvnw.cmd -B clean package
docker compose up -d --build --wait
docker compose ps -a     # all services healthy, vault-init "Exited (0)"
```

| Service | URL |
|---|---|
| App | http://localhost:8080 |
| Vault UI | http://localhost:8200 (token: the value in `.env`) |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3001 (user `admin`, password from Vault, see below) |

Read the Grafana password as admin. Never put a secret value in a screenshot.

```powershell
docker compose exec -T vault vault kv get -field=admin-password secret/grafana
```

Stop with `docker compose down`. Vault runs in dev mode (in memory), so the next start creates new secrets. `docker compose down -v` also deletes the volumes (audit log, bootstrap files).

## 8. Demo scenarios

Each demo follows the TP method: it works, then I break it, the control blocks it, then I fix it. Demos 1 and 2 also run on every pipeline run (step 7, [`scripts/test-vault-integration.sh`](scripts/test-vault-integration.sh)).

### Demo 1: the secret comes from Vault

```powershell
$key = docker compose exec -T vault vault kv get -field=api-key secret/democyber
curl.exe -i http://localhost:8080/api/secure                          # 401: no key
curl.exe -i -H "X-API-Key: wrong" http://localhost:8080/api/secure     # 401: wrong key
curl.exe -i -H "X-API-Key: $key" http://localhost:8080/api/secure      # 200: key from Vault
```

In Grafana, the Vault password works and `admin/admin` is refused.

### Demo 2: least privilege (no access, no start)

I replace the app's policy with one that denies its secret, then restart the app:

```powershell
docker compose exec -T vault vault policy write democyber /vault/policies/democyber-deny.hcl
docker compose restart democyber
Start-Sleep -Seconds 20
docker compose ps -a democyber      # Exited (1): the app refused to start
docker compose logs democyber | Select-String -Context 1,0 'permission denied' | Select-Object -Last 1
```

In Prometheus (Status → Targets), `democyber` is **DOWN**. Then I restore the policy:

```powershell
docker compose exec -T vault vault policy write democyber /vault/policies/democyber.hcl
docker compose up -d --no-deps --wait democyber    # starts the app again and waits until it is healthy
```

### Demo 3: rotation

Vault makes a new random key (a new version). The app reads it at its next start:

```powershell
$old = docker compose exec -T vault vault kv get -field=api-key secret/democyber
docker compose exec -T vault sh -c 'v=$(vault write -field=random_bytes sys/tools/random/32 format=hex); printf %s $v | vault kv put secret/democyber api-key=-'
docker compose exec -T vault vault kv metadata get secret/democyber    # current_version goes up by 1
docker compose restart democyber
docker compose up -d --no-deps --wait democyber                       # waits until healthy
$new = docker compose exec -T vault vault kv get -field=api-key secret/democyber
curl.exe -s -o NUL -w "old key -> %{http_code}`n" -H "X-API-Key: $old" http://localhost:8080/api/secure    # 401
curl.exe -s -o NUL -w "new key -> %{http_code}`n" -H "X-API-Key: $new" http://localhost:8080/api/secure    # 200
```

The new value reaches `vault kv put` on stdin (`api-key=-`), so it never appears in a command line.

### Demo 4: audit trail

```powershell
docker compose exec -T vault cat /vault/logs/audit.log |
  Select-String -Pattern '"path":"secret/(data/)?democyber"' |
  ForEach-Object { $_.Line | ConvertFrom-Json } |
  Where-Object type -eq 'response' |
  Select-Object time, @{n='who'; e={$_.auth.display_name}}, @{n='policies'; e={$_.auth.policies -join ','}}, @{n='operation'; e={$_.request.operation}}, @{n='path'; e={$_.request.path}}, @{n='result'; e={if ($_.error) {'DENIED'} else {'ok'}}} |
  Format-Table -AutoSize
```

One line per access to the app's secret: when, who (`token` with the `root` policy is me, `approle` with the `democyber` policy is the app) and the result. The `DENIED` row comes from Demo 2. Its path has no `data/`: Vault also refused to tell the app that `secret/` is a KV version 2 engine, so Spring Vault tried the old version 1 path, and Vault refused that too.

The secret value itself is never in the log, only its HMAC hash:

```powershell
docker compose exec -T vault cat /vault/logs/audit.log |
  Select-String -SimpleMatch '"path":"secret/data/democyber"' |
  ForEach-Object { $_.Line | ConvertFrom-Json } |
  Where-Object { $_.response.data.data.'api-key' } |
  Select-Object -Last 1 @{n='api-key in the audit log'; e={$_.response.data.data.'api-key'}}
```

### Demo 5: Gitleaks catches a Vault token

On a throwaway branch, I add a fake Vault token (`hvs.` and 95 random characters) to `application.properties` and open a pull request. The default Gitleaks rule `vault-service-token` finds it, and the pipeline fails at step 1. Then I close the pull request without merging and delete the branch, so `main` stays clean.

### Run the Vault integration test locally

It needs `.env` and the image `democyber-vault:local` (quick start). It replaces the running stack and removes it at the end.

```powershell
$bash = Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'bin\bash.exe'   # Git Bash
& $bash scripts/test-vault-integration.sh; "exit code: $LASTEXITCODE"                  # PASSED, 0
```

## 9. Monitoring

- Prometheus scrapes `democyber:8081/actuator/prometheus` every 5 seconds, Vault's `/v1/sys/metrics` (with its own token), and itself.
- Grafana is provisioned as code (data source and dashboards), so there are no manual clicks. The 2 dashboards are in the Grafana folder **Democyber**:

| Dashboard | Link | What it shows |
|---|---|---|
| **Democyber Security** (made for this project) | http://localhost:3001/d/democyber-security | app up, Vault up and unsealed, 401 (refused) vs 200 (accepted) on `/api/secure`, Vault requests, Vault answers by HTTP code (403 = access denied) |
| **Spring Boot 2.1 System Monitor** ([grafana.com ID 11378](https://grafana.com/grafana/dashboards/11378)) | http://localhost:3001/d/spring-boot-11378 | JVM memory, CPU, threads, garbage collection, HTTP traffic, log events |

- Every metric name in these dashboards was first checked against the real list in Prometheus.
- Dashboard 11378 is the community file (revision 2), with 4 changes only:
  1. its 47 `${DS_PROMETHEUS}` placeholders now point to our data source (uid `prometheus`);
  2. `__inputs` removed: only the manual "Import" window uses it;
  3. `__requires` removed: the same, a plugin list for that window;
  4. fixed uid `spring-boot-11378`, so the link never changes.
- On dashboard 11378, the HikariCP and Jetty panels stay empty: the app has no database, and it runs on Tomcat, not Jetty. Grafana 13 shows its old Graph and Singlestat panels (2019) as Time series and Stat panels. In the heap panels, `Max -1 B` means that the JVM sets no fixed limit for that memory pool (normal with the G1 garbage collector).
- `dashboards.yml`: a change made in the UI cannot be saved (`allowUiUpdates: false`), and a dashboard whose JSON file is removed is also removed from Grafana (`disableDeletion: false`). Git stays the only source of truth.
- Right after a start, the Grafana search page may not list the dashboards yet: Grafana builds its search index in the background. The links above always work.
- Grafana has no data volume on purpose: at each start it reads the current admin password from Vault.
- Grafana downloads no plugin at startup (`GF_PLUGINS_PREINSTALL_DISABLED`): it runs only the code of its pinned image.

## 10. Project structure

```text
devSecOps-Vault/
├── .github/workflows/ci.yml       # the CI/CD pipeline
├── src/main/...                   # Spring Boot app: /, /api/secure, Actuator; Vault settings in application.properties
├── src/test/...                   # web tests
├── vault/
│   ├── init/vault-init.sh         # bootstrap: secrets, policies, AppRoles, audit log
│   ├── policies/                  # democyber, grafana, metrics, democyber-deny (demo)
│   └── agent/                     # Vault Agent config and template for Grafana
├── monitoring/
│   ├── prometheus.yml             # scrape targets: the app, Vault, Prometheus
│   └── grafana/provisioning/      # Grafana as code (section 9)
│       ├── datasources/           # prometheus.yml: the Prometheus data source (uid prometheus)
│       └── dashboards/            # dashboards.yml (loader) and the 2 dashboard JSON files
├── scripts/
│   ├── smoke-test.sh              # CI step 5
│   └── test-vault-integration.sh  # CI step 7, also runs locally (section 8)
├── Dockerfile                     # non-root runtime image
├── compose.yml                    # vault, vault-init, democyber, vault-agent, prometheus, grafana
├── pom.xml                        # Maven build: Spring Boot, Spring Cloud Vault, Java 21
├── .env.example                   # VAULT_DEV_ROOT_TOKEN_ID only
├── .gitattributes                 # LF line endings for everything that runs in Linux
├── .gitignore                     # target/, .env, local scan reports
├── .dockerignore                  # only the JAR goes to the Docker build
├── mvnw, mvnw.cmd, .mvn/          # Maven Wrapper
└── README.md
```

## 11. Evidence for the report

- [ ] Green pipeline run on `main`, all steps visible
- [ ] Gitleaks and Trivy artifacts
- [ ] SonarCloud Quality Gate passed
- [ ] Docker Hub: tags `<sha>` and `latest`
- [ ] Pull request run: the publish steps are skipped
- [ ] Red pull request run: Gitleaks catches the fake Vault token
- [ ] `docker compose ps -a`: all services healthy, ports on `127.0.0.1`
- [ ] Vault UI: secrets engine, policies, AppRole auth method, audit device
- [ ] Demos 1 to 4 in the terminal, with no secret value visible
- [ ] Vault integration test: PASSED, then FAILED with the deny policy broken on purpose, then PASSED again
- [ ] Prometheus targets all UP, then `democyber` DOWN during Demo 2
- [ ] Grafana: Spring Boot and Democyber Security dashboards
- [ ] SonarQube Cloud: 6 dependency risks before the Bouncy Castle pin, 3 after (section 12)

## 12. Security review

Threat by threat: what protects the project, the proof, and what is still open.

| # | Threat | Control in this project | Evidence | Still open / next step |
|---|---|---|---|---|
| 1 | A secret is committed to Git | Gitleaks checks the commits of every push and pull request (step 1); `.env` is git-ignored | Demo 5: pull request #6 fails at step 1. Local scan of the full history: 0 leaks | Gitleaks runs after the push. GitHub secret scanning did not flag the fake Vault token, so Gitleaks is still needed. Next: a pre-commit hook |
| 2 | An API key or a password is written in the code | Vault generates the values (`sys/tools/random`); the app and Grafana get them at startup | Demo 1 and step 7; `admin/admin` is refused | A new key needs an app restart (Demo 3) |
| 3 | A stolen app login reads other secrets | One read-only policy per client, for one path only | Demo 2 and step 7: access denied, so the app does not start | Production: short token TTLs and an AppRole bound to the app's network (CIDR) |
| 4 | Someone copies the app's Vault login (`secret-id`) | Each login file is in a private volume that only its client can read (section 6.2) | Design in `vault-init.sh` and `compose.yml` | "Secret zero" (section 6.4): platform identity or single-use `secret-id` |
| 5 | Nobody knows who read a secret | Vault audit log; secret values are HMAC hashes | Demo 4: `root` vs `democyber`, and the `DENIED` row | The log stays on this laptop. Production: send it to a SIEM |
| 6 | A vulnerable library or base image | Trivy blocks HIGH and CRITICAL (step 6); SonarQube Cloud also lists dependency risks; pinned versions | `trivy-report` artifact on every run; Bouncy Castle pinned to 1.87 (table below) | 3 lower risks accepted (table below). Dependabot alerts are off in the GitHub settings. Next: turn them on |
| 7 | Bad code reaches `main` | Web tests; SonarCloud Quality Gate, the job waits for it (step 3) | Quality Gate passed, 0 issues | Coverage is 0%: no JaCoCo report yet |
| 8 | Changed third-party code runs in the pipeline | Actions pinned by commit SHA, Docker images pinned to a version, no Grafana plugin download | `ci.yml`, `compose.yml` | Images are not signed (Cosign) |
| 9 | A pipeline token leaks | GitHub Secrets; read-only `GITHUB_TOKEN`; values hidden with `::add-mask::`; pull requests never publish | Pull request runs: the publish steps are skipped | Static tokens. Next: OIDC ([section 13](#13-limits-and-next-steps)) |
| 10 | A change reaches `main` without review | Since the pipeline exists, every change came through a pull request with a green run | Pull requests #1, #3, #4, #5 (#2 and #6: red demos, never merged) | No branch protection yet: `main` should require a pull request and green checks |
| 11 | A service is open to the network | Every port is bound to `127.0.0.1`; Actuator is on port `8081`, not published | `docker compose ps -a`; smoke test (step 5) | — |
| 12 | A container runs as root | The app runs as user `10001`; Vault and Vault Agent run as `vault` | `Dockerfile`; SonarCloud: 0 issues | `vault-init` runs as root, with one capability only (`CHOWN`) |
| 13 | The Vault root token leaks | Dev mode only; the token is only in `.env` (git-ignored) | Gitleaks green; section 6.3 | Dev mode is for demos only ([section 13](#13-limits-and-next-steps)) |
| 14 | Nobody knows how to report a security problem | — | — | No `SECURITY.md` yet |

**Dependency risks found by SonarQube Cloud (25 November 2026)**

| Library (how it comes in) | CVE | CVSS | Decision |
|---|---|---|---|
| Bouncy Castle `bcprov-jdk18on` 1.85.2 (via `spring-cloud-starter`) | CVE-2026-18036, CVE-2026-71886, CVE-2026-71891 | 7.1 to 8.2 (High) | **Fixed**: pinned to 1.87 in `pom.xml` (these CVEs are fixed since 1.86) |
| `logback-classic` 1.5.38 (Spring Boot logging) | CVE-2026-104721 | not scored yet | Accepted for now: the bug is in the MDC-based `SiftingAppender`, which this app does not use. The fix exists only in logback 1.6.5 and later, and Spring Boot 4.1 still ships 1.5.38 |
| `json-smart` 2.6.0 (tests only) | CVE-2026-113602 | 6.9 (Medium) | Accepted: test scope only, not in the image |
| `HdrHistogram` 2.2.2 (via Micrometer) | CVE-2026-14686 | 1.9 (Low) | Accepted: low risk |

## 13. Limits and next steps

- **Dev mode** keeps data in memory, and anyone who controls Docker on this laptop can see the root token (in `.env`, in `docker inspect` and in the Vault startup log). Next step: server mode with Raft storage, TLS and unseal keys.
- **Secret zero**: use a platform identity or wrapped, single-use `secret-id`s.
- **CI secrets** are still GitHub Secrets. Next step: GitHub OIDC login to Vault (JWT auth), which needs a Vault that GitHub can reach.
- **Dynamic database credentials** that expire on their own.
- **Vault as code** with Terraform.
- **Image signing** with Cosign, verified before deployment.
- **OpenBao**: the open-source fork of Vault, with a compatible API.
