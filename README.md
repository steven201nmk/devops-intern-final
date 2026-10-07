# DevOps Intern Final Assessment

[![CI/CD Pipeline](https://github.com/steven201nmk/devops-intern-final/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/steven201nmk/devops-intern-final/actions/workflows/ci.yml)

| | |
|---|---|
| **Name** | Nyi Min Khant |
| **GitHub** | [@steven201nmk](https://github.com/steven201nmk) |
| **Submission date** | TODO: YYYY-MM-DD |
| **Release tag** | [`v1.0.0`](https://github.com/steven201nmk/devops-intern-final/tree/v1.0.0) |
| **Container image** | [`ghcr.io/steven201nmk/devops-intern-final/nginx-app`](https://github.com/steven201nmk/devops-intern-final/pkgs/container/devops-intern-final%2Fnginx-app) |

An end-to-end deployment pipeline for a containerised NGINX web application:
source control → automated CI → container registry → Nomad deployment → log aggregation in Grafana Loki.
Based on [chakilams/simple-nginx-app](https://github.com/chakilams/simple-nginx-app), with the Kubernetes manifests replaced by a Nomad job.

## Contents

1. [Architecture](#architecture)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Repository Layout](#repository-layout)
5. [Task 1 — Source Control](#task-1--source-control)
6. [Task 2 — Linux Scripting](#task-2--linux-scripting)
7. [Task 3 — Containerisation](#task-3--containerisation)
8. [Task 4 — Continuous Integration](#task-4--continuous-integration)
9. [Task 5 — Orchestration with Nomad](#task-5--orchestration-with-nomad)
10. [Task 6 — Log Aggregation with Grafana Loki](#task-6--log-aggregation-with-grafana-loki)
11. [Troubleshooting](#troubleshooting)
12. [Known Limitations](#known-limitations)

---

## Architecture

Every stage consumes the output of the one before it. A commit to `main` is linted, built and tested by GitHub Actions. The tested image is pushed to GHCR, tagged with the commit SHA. Nomad deploys that exact SHA tag and registers the service with Consul, which health-checks `/healthz`. Promtail ships the container's NGINX access logs to Loki, where they are queried in Grafana.

```text
  ┌─────────────────────┐
  │  Source (GitHub)    │  feature/* branch -> pull request -> main
  └──────────┬──────────┘
             │ push / pull_request
             ▼
  ┌─────────────────────┐
  │  CI (GitHub Actions)│  lint -> build -> test -> publish
  └──────────┬──────────┘
             │ docker push  :<git-sha>  :latest
             ▼
  ┌─────────────────────┐
  │  Registry (GHCR)    │  ghcr.io/steven201nmk/devops-intern-final/nginx-app
  └──────────┬──────────┘
             │ docker pull  :<git-sha>   (Nomad variable app_tag)
             ▼
  ┌─────────────────────┐        ┌──────────────────────┐
  │  Nomad (docker)     │───────>│  Consul              │
  │  job nginx-app      │register│  check GET /healthz  │
  └──────────┬──────────┘        └──────────────────────┘
             │ container stdout (NGINX access logs)
             ▼
  ┌─────────────────────┐        ┌──────────────────────┐
  │  Promtail -> Loki   │<───────│  Grafana (Explore)   │
  │  labels: job,       │ LogQL  │  localhost:3000      │
  │  container, alloc_id│        └──────────────────────┘
  └─────────────────────┘
```

| Stage | Input | Output | Defined in |
|---|---|---|---|
| Source | Code changes on a `feature/*` branch | Merged commit on `main` | Git / GitHub |
| CI | Commit on `main` | Tested image | `.github/workflows/ci.yml` |
| Registry | Tested image | `nginx-app:<git-sha>` and `:latest` in GHCR | `publish` job |
| Orchestration | `nginx-app:<git-sha>` | Healthy allocation registered in Consul | `nomad/nginx-app.nomad.hcl` |
| Observability | Container stdout | Labelled log streams in Loki | `monitoring/` |

---

## Prerequisites

Tested on: TODO (for example, Ubuntu 24.04 under WSL2)

| Tool | Version used | Check with |
|---|---|---|
| Docker Engine | TODO | `docker version` |
| Docker Compose (v2 plugin) | TODO | `docker compose version` |
| HashiCorp Nomad | TODO | `nomad version` |
| HashiCorp Consul | TODO | `consul version` |
| ShellCheck | TODO | `shellcheck --version` |
| hadolint | TODO | `hadolint --version` |
| git, curl | any recent | `git --version`, `curl --version` |

---

## Quick Start

From a clean clone to the running application in five commands:

```bash
git clone https://github.com/steven201nmk/devops-intern-final.git
cd devops-intern-final
docker build --build-arg BUILD_SHA="$(git rev-parse --short HEAD)" -t nginx-app:local ./app
docker run -d --name nginx-app -p 8080:8080 nginx-app:local
./scripts/healthcheck.sh http://localhost:8080/healthz
```

Open <http://localhost:8080> to see the page with my name, the assessment date and the build SHA.
Clean up with `docker rm -f nginx-app`.

To deploy with Nomad instead, see [Task 5](#task-5--orchestration-with-nomad). For the logging stack, see [Task 6](#task-6--log-aggregation-with-grafana-loki).

---

## Repository Layout

```text
devops-intern-final/
├── README.md
├── .gitignore
├── .gitattributes          # keeps every text file LF (Windows-safe)
├── app/
│   ├── Dockerfile              # pinned nginx:1.27-alpine, non-root, HEALTHCHECK
│   ├── index.html              # name, date, BUILD_SHA placeholder
│   └── nginx.conf              # listens on 8080, /healthz returns 200
├── scripts/
│   ├── sysinfo.sh              # host environment report
│   └── healthcheck.sh          # asserts HTTP 200 on a URL
├── .github/
│   └── workflows/
│       └── ci.yml              # lint -> build -> test -> publish
├── nomad/
│   └── nginx-app.nomad.hcl     # service job, Consul check, rolling update
├── monitoring/
│   ├── loki-config.yaml
│   ├── promtail-config.yaml
│   ├── docker-compose.yaml     # Loki + Promtail + Grafana
│   └── loki_setup.md           # detailed Loki notes
└── docs/
    └── screenshots/
```

---

## Task 1 — Source Control

**Workflow used**

- All changes are made on `feature/*` branches and merged to `main` through a pull request with a short description.
  - Merged PR: TODO: link, for example `https://github.com/steven201nmk/devops-intern-final/pull/1`
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `ci:`.
- IDE metadata (`.idea/`, `.vscode/`), build artefacts and local secrets (`.env`, `*.pem`) are excluded by `.gitignore`.
- The final state is tagged `v1.0.0`.

**Commands**

```bash
git switch -c feature/<short-name>
git add <files>
git commit -m "feat: <what changed>"
git push -u origin feature/<short-name>
# open a pull request to main on GitHub, self-review it, then merge

git switch main && git pull
git tag -a v1.0.0 -m "v1.0.0: final submission"
git push origin v1.0.0
```

**Observed output:** `git log --oneline --graph --decorate -20`

```text
TODO: paste output
```

---

## Task 2 — Linux Scripting

Both scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`. They use bash rather than `/bin/sh` because `pipefail` isn't available in `dash`, which is `/bin/sh` on Ubuntu. Otherwise they only use POSIX utilities. Both are committed as executable (`git update-index --chmod=+x`, mode `100755`) and pass ShellCheck with no findings.

| Script | Purpose | Exit codes |
|---|---|---|
| `scripts/sysinfo.sh` | Prints the current user and effective UID, hostname, kernel release, ISO-8601 date (UTC), disk usage, memory usage and Docker daemon status | `0` |
| `scripts/healthcheck.sh [URL]` | Requests `URL` (default `http://localhost:8080`) and checks that the status is exactly `200`. It prints the status code it received | `0` = 200, `1` = other status, `2` = unreachable, `3` = curl missing |

**Lint and permissions**

```bash
shellcheck scripts/*.sh && echo "ShellCheck: no issues"
git ls-files -s scripts/          # mode 100755 means executable in Git
```

```text
TODO: paste output
```

**`sysinfo.sh`**

```bash
./scripts/sysinfo.sh
```

```text
TODO: paste output
```

**`healthcheck.sh`, success and failure cases**

```bash
./scripts/healthcheck.sh;                                   echo "exit=$?"   # default URL
./scripts/healthcheck.sh http://localhost:8080/healthz;     echo "exit=$?"
./scripts/healthcheck.sh http://localhost:8080/missing;     echo "exit=$?"   # 404
./scripts/healthcheck.sh http://localhost:9999;             echo "exit=$?"   # nothing listening
```

```text
TODO: paste output
```

---

## Task 3 — Containerisation

| Requirement | How it is met |
|---|---|
| Pinned base image | `FROM nginx:1.27-alpine` (never `latest`) |
| Port 8080 and `/healthz` | `app/nginx.conf`: `listen 8080;` and `location = /healthz` returns `200 OK` as `text/plain`, with `access_log off` so health probes don't flood the logs |
| Non-root runtime | `USER nginx` (UID 101). The PID file and temp paths are moved to `/tmp` so NGINX can start without root |
| `EXPOSE` and `HEALTHCHECK` | `EXPOSE 8080`, and the `HEALTHCHECK` curls `/healthz` every 10 s |
| Build identifier | `ARG BUILD_SHA` is written into `index.html` at build time and recorded as the `org.opencontainers.image.revision` label |
| Image under 60 MB | TODO MB (see `docker images` below) |

**Build and run**

```bash
docker build --build-arg BUILD_SHA="$(git rev-parse --short HEAD)" -t nginx-app:local ./app
docker images nginx-app:local
docker run -d --name nginx-app -p 8080:8080 nginx-app:local
```

```text
TODO: paste output (including the SIZE column)
```

**Serving traffic**

```bash
curl -i http://localhost:8080/
curl -i http://localhost:8080/healthz
```

```text
TODO: paste output
```

**Non-root and health status**

```bash
hadolint app/Dockerfile && echo "hadolint: no issues"
docker exec nginx-app id
docker inspect --format '{{.State.Health.Status}}' nginx-app
```

```text
TODO: paste output
```

![Application page showing name, date and build SHA](docs/screenshots/app-browser.png)

---

## Task 4 — Continuous Integration

`.github/workflows/ci.yml` runs on every push and pull request to `main`.

| Job | What it does | Runs on |
|---|---|---|
| `lint` | `shellcheck scripts/*.sh`, then hadolint (pinned `hadolint/hadolint:v2.12.0` image) on `app/Dockerfile` | push and PR |
| `build` | `docker build --build-arg BUILD_SHA=${{ github.sha }}`, then saves the image as a workflow artifact | push and PR |
| `test` | Loads that exact image, starts it, waits until the Docker `HEALTHCHECK` reports `healthy`, then runs `scripts/healthcheck.sh` against `/` and `/healthz` and checks that the page contains the commit SHA. Any non-200 fails the job, so `publish` never runs | push and PR |
| `publish` | Pushes the tested image (not a rebuild) to GHCR as `:${{ github.sha }}` and `:latest` | push to `main` only |

**Security**

- Registry login uses the short-lived `GITHUB_TOKEN`, passed through `--password-stdin`. No personal tokens or other long-lived credentials are stored in the repository.
- The workflow's default `permissions` are `contents: read`. Only the `publish` job is granted `packages: write`.
- Only GitHub's own actions are used, each pinned to a major version: `actions/checkout@v5`, `actions/upload-artifact@v7` and `actions/download-artifact@v8`. Hadolint runs from a pinned image tag. No third-party marketplace actions are used.

**Evidence**

- Green run on `main`: TODO: link to the run
- Published image tags: TODO: list the SHA tag and `latest`

```bash
docker pull ghcr.io/steven201nmk/devops-intern-final/nginx-app:<git-sha>
```

```text
TODO: paste output
```

![Green CI pipeline on main](docs/screenshots/ci-green.png)

![Image published in GHCR with SHA and latest tags](docs/screenshots/ghcr-package.png)

---

## Task 5 — Orchestration with Nomad

`nomad/nginx-app.nomad.hcl` deploys the image that CI published. It pulls the image by commit SHA, and the tag is set with the `app_tag` variable. The variable has no default, and a `validation` rule rejects `latest`, so every deployment is pinned to a commit.

| Requirement | Setting |
|---|---|
| Job type | `type = "service"`, one group (`web`), one task (`nginx`), `docker` driver |
| Image | `ghcr.io/steven201nmk/devops-intern-final/nginx-app:${var.app_tag}` |
| Resources | `cpu = 100` (MHz), `memory = 64` (MB). These are the values in the brief, with no deviation |
| Networking | Dynamic port named `http`, mapped to container port `8080` |
| Service discovery | Consul service `nginx-app` with an HTTP check on `/healthz`, `interval = "10s"`, `timeout = "2s"`. `check_restart` restarts the task after 3 failed checks |
| Rolling update | `max_parallel = 1`, `min_healthy_time = "10s"`, `healthy_deadline = "2m"`, `auto_revert = true` |
| Failure handling | `restart`: 2 in-place restarts per minute, then fail. `reschedule`: up to 3 new placements in 5 minutes, with exponential back-off |
| Log labels | Docker labels `job` and `service` (`nginx-app`) for Promtail. Nomad adds `com.hashicorp.nomad.alloc_id` itself |

**Start local agents**, each in its own terminal:

```bash
consul agent -dev
sudo nomad agent -dev        # root is needed for the docker driver on Linux
```

**Validate, plan, run and check status**

```bash
export SHA="$(git rev-parse HEAD)"     # full 40-character SHA, the same tag CI pushed

nomad job validate -var "app_tag=$SHA" nomad/nginx-app.nomad.hcl
nomad job plan     -var "app_tag=$SHA" nomad/nginx-app.nomad.hcl
nomad job run      -var "app_tag=$SHA" nomad/nginx-app.nomad.hcl
nomad job status nginx-app
```

```text
TODO: paste output of each command
```

**Allocation health and Consul check**

```bash
nomad alloc status <alloc-id>                           # shows the dynamic port for "http"
curl -i http://127.0.0.1:<dynamic-port>/healthz
curl -s http://127.0.0.1:8500/v1/health/checks/nginx-app
```

```text
TODO: paste output
```

![Nomad UI showing the nginx-app allocation healthy](docs/screenshots/nomad-job-healthy.png)

![Consul UI showing the nginx-app /healthz check passing](docs/screenshots/consul-health.png)

---

## Task 6 — Log Aggregation with Grafana Loki

Full notes, including the problems I hit, are in [`monitoring/loki_setup.md`](monitoring/loki_setup.md).

**Start the stack**

```bash
cd monitoring
docker compose up -d
docker compose ps
```

```text
TODO: paste output
```

**Labels applied by Promtail** (Docker service discovery through `/var/run/docker.sock`)

| Label | Source |
|---|---|
| `job` | Docker label `job`, set in the Nomad job's `labels` block (`nginx-app`). Containers without it get `docker` |
| `container` | Docker container name, with the leading `/` removed |
| `nomad_alloc_id` | Docker label `com.hashicorp.nomad.alloc_id`, which Nomad's docker driver always adds |
| `service` | Docker label `service` (Nomad job), or the compose service name |
| `stream` | `stdout` (NGINX access log) or `stderr` (NGINX error log) |

**Generate traffic, including errors**

```bash
PORT=<dynamic-port-from-task-5>
for i in 1 2 3 4 5; do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/"
  curl -s -o /dev/null "http://127.0.0.1:$PORT/does-not-exist"
done
curl -s http://localhost:3100/loki/api/v1/labels
```

```text
TODO: paste output
```

**Grafana**

Open <http://localhost:3000> and go to **Connections → Data sources → Add data source → Loki**. Set the URL to `http://loki:3100`, then click **Save & test** and open **Explore**.

**LogQL queries**

```logql
# Q1 - every NGINX access-log line
{job="nginx-app", stream="stdout"}

# Q2 - only non-2xx responses: isolates the 404s from the missing path
{job="nginx-app", stream="stdout"} |~ "\" [45][0-9]{2} "

# Q3 - the same, but parsing each line into fields first
{job="nginx-app", stream="stdout"}
  | pattern `<ip> - <_> [<_>] "<method> <path> <_>" <status> <_>`
  | status != "200"

# Q4 - requests per status code over the last 10 minutes
sum by (status) (
  count_over_time({job="nginx-app", stream="stdout"}
    | pattern `<ip> - <_> [<_>] "<method> <path> <_>" <status> <_>` [10m])
)
```

`stream="stdout"` keeps NGINX's stderr error lines (`open() ... failed`) out of the results.

**Results**

TODO: describe what each query returned. For example: Q2 and Q3 returned only the 5 `GET /does-not-exist HTTP/1.1" 404` lines, and Q4 showed `200` → 5 and `404` → 5.

![Grafana Explore filtering NGINX access logs for non-200 responses](docs/screenshots/grafana-explore.png)

---

## Troubleshooting

These are failures I actually hit while building this project, in the order they happened.

### 1. CI could not find the ShellCheck action

- **Symptom:** TODO: paste the exact error from the failed run
- **Cause:** The action referenced in `ci.yml` was not a valid, resolvable repository.
- **Fix:** ShellCheck is preinstalled on GitHub's Ubuntu runners, so the lint job now calls `shellcheck scripts/*.sh` directly. See commits [`19a873b`](https://github.com/steven201nmk/devops-intern-final/commit/19a873b) and [`ee60dad`](https://github.com/steven201nmk/devops-intern-final/commit/ee60dad).

### 2. Windows line endings (CRLF) broke the shell scripts

- **Symptom:** TODO: paste the error, for example ShellCheck `SC1017` (literal carriage return) or `/bin/sh^M: bad interpreter`
- **Cause:** The scripts were saved on Windows with CRLF line endings. Linux shells treat the `\r` as part of each command.
- **Fix:** Converted the scripts to LF. Adding a `.gitattributes` with `*.sh text eol=lf` stops it from happening again. See commits [`ca417af`](https://github.com/steven201nmk/devops-intern-final/commit/ca417af) and [`80ac98d`](https://github.com/steven201nmk/devops-intern-final/commit/80ac98d).

### 3. UTF-8 BOM in `nginx.conf` stopped NGINX from starting

- **Symptom:** TODO: paste the `nginx: [emerg] ...` error from `docker logs`
- **Cause:** The Windows editor saved the file as "UTF-8 with BOM". The invisible bytes `EF BB BF` before the first directive made NGINX reject the first line.
- **Fix:** Re-saved the file as UTF-8 without a BOM. Check for it with `head -c 3 app/nginx.conf | xxd`. See commits [`a0a62e3`](https://github.com/steven201nmk/devops-intern-final/commit/a0a62e3), [`3c839f0`](https://github.com/steven201nmk/devops-intern-final/commit/3c839f0) and [`45e2138`](https://github.com/steven201nmk/devops-intern-final/commit/45e2138).

### 4. NGINX failed when running as a non-root user

- **Symptom:** TODO: paste the error, for example `open() "/var/run/nginx.pid" failed (13: Permission denied)`
- **Cause:** By default NGINX writes its PID file and temp files to root-owned paths and listens on port 80, which a non-root user cannot bind.
- **Fix:** Moved `pid` and every `*_temp_path` to `/tmp`, set `listen 8080`, and `chown`ed the cache and log directories to `nginx`. Updated the CI test job to map port `8080:8080`. See commits [`1a8fb67`](https://github.com/steven201nmk/devops-intern-final/commit/1a8fb67), [`67fc5d9`](https://github.com/steven201nmk/devops-intern-final/commit/67fc5d9) and [`998c660`](https://github.com/steven201nmk/devops-intern-final/commit/998c660).

---

## Known Limitations

These parts of the submission are not production-ready:

- **Single-node dev agents.** Nomad and Consul run with `-dev`: one node, in-memory state, no ACLs, no TLS and no gossip encryption. In production I would run a 3-server cluster with ACLs and mTLS enabled.
- **No TLS on the application.** NGINX serves plain HTTP on port 8080.
- **Grafana is open.** Anonymous access with the Admin role is enabled for convenience, and the Loki data source is added by hand. With more time I would turn on authentication and provision the data source from a committed file.
- **Loki storage.** Loki is a single binary using local filesystem storage with no retention policy. Production would need object storage (S3 or GCS) and retention limits.
- **Promtail is deprecated.** Grafana now recommends Grafana Alloy as the log collector. I would migrate to it.
- **Supply chain.** Actions are pinned to major versions rather than commit SHAs. Images are not scanned (for example with Trivy), signed (cosign) or shipped with an SBOM.
- **Deployment is manual.** CI publishes the image, but the Nomad job is run by hand. Next steps would be a deploy job, or a `nomad-pack`/Terraform workflow.
- **`latest` is still published.** It is kept only for convenience. Deployments always use the immutable SHA tag.

TODO: add anything else you know is weak in your submission.
