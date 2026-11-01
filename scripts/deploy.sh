#!/bin/bash
# Runs ON THE SERVER as the deployer user. The pipeline sends it over SSH:
#   ssh target "IMAGE_TAG=<sha> bash -s" < scripts/deploy.sh
set -euo pipefail

cd /home/deployer/app

if [ -z "${IMAGE_TAG:-}" ]; then
  echo "IMAGE_TAG is not set" >&2
  exit 1
fi
export IMAGE_TAG

if [ ! -f .env ]; then
  echo "Missing /home/deployer/app/.env - create it once by hand" >&2
  exit 1
fi

echo "==> Deploying image tag $IMAGE_TAG"
docker compose pull
docker compose up -d --remove-orphans

# Nginx looks up the API's address when it starts. Reload so it finds the
# new API container if it was recreated.
docker compose exec -T nginx nginx -s reload

echo "==> Waiting for the API to answer"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if curl -fsS http://localhost/health; then
    echo
    echo "==> Healthy"
    docker image prune -af --filter "until=168h"
    exit 0
  fi
  sleep 5
done

echo "Health check failed" >&2
docker compose ps
docker compose logs --tail 50 api
exit 1