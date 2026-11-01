# Task Tracker: a small DevOps practice project

A tiny two-tier web app (Nginx, a Flask API, PostgreSQL) used to practise the full DevOps path: containers, server preparation, infrastructure as code, a CI/CD pipeline, and monitoring. Everything is in this one repository, so a single `git clone` gives you the app, the infrastructure, the scripts, and the pipeline.

The section [What has and has not been tested](#what-has-and-has-not-been-tested) says plainly what was verified and what was only written.

## Architecture

```
Internet --> Nginx (:80) --> API (:5000) --> PostgreSQL
                frontend-net     backend-net

Prometheus --> node-exporter, blackbox-exporter (probes the API's /health)
Grafana    --> Prometheus                          (monitoring-net)
```

- **Nginx** is the only service published to the network (port 80). It is on `frontend-net` only, so it cannot reach the database.
- **API** (Flask + gunicorn) is on both networks. It runs as a non-root user (`appuser`).
- **PostgreSQL** is on `backend-net` only. Its data lives in the `db-data` volume.
- **Prometheus and Grafana** are published on `127.0.0.1` only, so they are reached through an SSH tunnel. The blackbox exporter is the one monitoring container that also joins `frontend-net`, so it can probe the API.

API endpoints: `/` (greeting), `/health` (returns `{"status":"ok"}`), `/counter` (increments a number stored in PostgreSQL).

## Repository layout

```
.github/workflows/deploy.yml   CI/CD pipeline
app/                           Flask app, Dockerfile, tests
nginx/nginx.conf               reverse proxy to the API
monitoring/                    Prometheus config, alert rules, Grafana provisioning
scripts/init-server.sh         prepares a fresh Ubuntu server
scripts/clean-logs.sh          deletes old logs (installed as a cron job)
scripts/deploy.sh              runs on the server during a deploy
infra/                         Terraform (see infra/README.md)
docker-compose.yml             the stack as run on the server
docker-compose.override.yml    local-only changes (builds the API from source)
.env.example                   variable names with placeholder values
```

## Prerequisites

- Docker with the Compose plugin
- Python 3.11 (only to run the tests outside Docker)
- Terraform 1.16.x, an AWS account, and an SSH key pair (only for the cloud part)
- A GitHub account (for the pipeline and the container registry)

## Run it locally

```
copy .env.example .env
```

Edit `.env` and set real values for all four variables (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `GRAFANA_ADMIN_PASSWORD`). Then:

```
docker compose up -d --build
curl http://localhost/health
curl http://localhost/counter
```

Docker Compose loads `docker-compose.override.yml` automatically on your machine, so the API is built from `./app`. On a server, only `docker-compose.yml` is present, so the image is pulled from the registry instead.

Prometheus is at http://localhost:9090 and Grafana at http://localhost:3000 (user `admin`, the password from `.env`). In Grafana, a Prometheus data source is created automatically from `monitoring/grafana/provisioning`. To get a dashboard, open Dashboards, then Import, enter ID `1860` (Node Exporter Full), and pick the Prometheus data source.

Note for Docker Desktop on Windows: the override file mounts the host's root folder for node-exporter without the `rslave` option, which Docker Desktop does not support. Locally this shows the metrics of Docker's virtual machine, not of your PC.

Run the tests without Docker:

```
cd app
pip install -r requirements.txt pytest
python -m pytest tests -q
```

Stop everything with `docker compose down`. This keeps the database. `docker compose down -v` also deletes the volumes, and with them all data.

## Create the server (Terraform)

The `infra/` folder builds a VPC, a public subnet, a security group (SSH from one IP, HTTP from anywhere), an SSH key pair, and one Ubuntu 24.04 EC2 instance. On first boot the instance runs `scripts/init-server.sh`, which installs Docker, creates a non-root `deployer` user, enables the firewall, and installs a daily log-cleanup job. See [infra/README.md](infra/README.md) for the commands and for what has been tested.

## The pipeline

File: `.github/workflows/deploy.yml`. It runs on every push to `main`, on pull requests, and manually.

1. **Lint and test**: hadolint on the Dockerfile, shellcheck on `scripts/*.sh`, then pytest.
2. **Terraform format and validate**: `terraform fmt -check`, `init -backend=false`, `validate`.
3. **Build and push image** (waits for 1 and 2): builds the image and, only on `main`, pushes it to GitHub Container Registry as `ghcr.io/samibirhanu1/devops-practice-project/api`, tagged with the commit SHA and `latest`. Pull requests build but do not push.
4. **Deploy to server** (waits for 3): runs only on `main`, and only when the repository variable `DEPLOY_ENABLED` is `true`. Until then it shows as skipped. It connects over SSH with a pinned host key, copies `docker-compose.yml`, `nginx/nginx.conf`, and `monitoring/` to the server, then runs `scripts/deploy.sh`. That script pulls the image for the exact commit SHA, restarts only what changed, reloads Nginx and Prometheus, and waits for `/health` to answer. The job then checks `/health` again from outside.

Design choices: the deploy job uses the SSH client already on the runner instead of a third-party SSH action, because the job holds the private key to the server. Deploying by commit SHA means every release is traceable, and a rollback is the same deploy with an older SHA.

### GitHub settings the deploy job needs

| Name | Type | Value |
|---|---|---|
| `SERVER_HOST` | Secret | The server's public IP or name |
| `SSH_PRIVATE_KEY` | Secret | Private key whose public half is on the server for `deployer` |
| `SERVER_HOST_KEY` | Secret | Output of `ssh-keyscan -t ed25519 SERVER_IP` |
| `DEPLOY_ENABLED` | Variable | `true` to switch the deploy job on |

The registry package is public, so the server pulls without logging in. For a private package, the deploy script would need a `docker login` step with a read-only token, which is not implemented.

## First-time server setup

1. `terraform apply` in `infra/` and note the printed `public_ip`.
2. Create `/home/deployer/app/.env` on the server by hand, with **new** random values for all four variables. It is deliberately not in Git and not copied by the pipeline.
3. Add the secrets and the variable from the table above in GitHub: Settings, Secrets and variables, Actions.
4. Push to `main` and watch the Actions tab. Then check `http://SERVER_IP/health`.
5. To see Grafana or Prometheus: `ssh -L 3000:localhost:3000 -L 9090:localhost:9090 deployer@SERVER_IP`, then open `http://localhost:3000` or `http://localhost:9090`.

Rollback: on the server, run `IMAGE_TAG=<older commit SHA> docker compose up -d` in `/home/deployer/app`.

## Alerts

`monitoring/alerts.yml` defines two rules:

- `ApiDown`: the blackbox probe of `/health` has failed for 1 minute.
- `LowDiskSpace`: less than 15% of the root disk is free, for 5 minutes.

Alerts show in the Prometheus UI. Nothing sends notifications yet (see limitations).

## Security notes

- `.env`, Terraform state, `*.tfvars`, and key files are git-ignored. The full Git history was searched for the project's passwords and private-key headers, with no matches.
- The API container runs as a non-root user, and the database is not reachable from Nginx.
- SSH access on the server is limited to one IP address by the security group.
- The deploy user can run Docker, which is close to root access, so its key must be protected.

## What has and has not been tested

| Item | Status |
|---|---|
| App tests (pytest), Dockerfile lint, shell script lint, Terraform format and validate | Run automatically on every push; the latest runs are green |
| Docker image build and push to the registry with SHA and `latest` tags | Done in the pipeline |
| Pulling the published image by SHA and starting the stack in a clean folder | Done locally |
| Local stack (Nginx, API, database, monitoring): start, counter, persistence | Done locally |
| `docker compose up -d` run twice | Done: no errors, nothing recreated |
| API recovery after its main process exits | Done: Docker restarted it automatically. A manual `docker kill` did not trigger a restart |
| `ApiDown` alert | Done locally: stopped the API and watched the alert fire |
| `init-server.sh` | Tested twice in a blank Ubuntu container with the firewall and Docker steps skipped |
| `terraform plan` and `apply` against real AWS | **Not run** (no AWS account used yet) |
| `terraform apply` twice | **Not run.** The practice was done with the `local` provider only |
| Docker install, firewall, systemd, and cron firing on a real server | **Not tested** |
| Deploy job (SSH, copy files, `deploy.sh`) on a real server | **Not tested.** It is written and switched off |
| `LowDiskSpace` alert | **Syntax checked only.** Docker Desktop's VM has no filesystem at `/`, so the query returns nothing locally |
| Service recovery after a server reboot | **Not tested** |

## Known limitations

- **SSH from the pipeline:** the security group allows port 22 from one IP only, so a GitHub-hosted runner cannot reach the server. Options are a self-hosted runner, AWS Systems Manager, or temporarily opening the port during a deploy.
- **No HTTPS:** only plain HTTP on port 80.
- **Alerts do not notify:** there is no Alertmanager, so there is no email or chat message.
- **Dashboard is imported by hand:** the Grafana data source is in Git, the dashboard is not.
- **Terraform state is local.** A team would use a remote backend with locking.
- **Logs are deleted after 7 days** without being shipped anywhere first.
- **The `latest` tag moves;** deploys use the commit SHA for that reason.
