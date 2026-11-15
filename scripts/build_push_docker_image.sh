#!/usr/bin/env bash
# Builds the job-matcher image and pushes it to ECR. The next run (scheduled or manual)
# uses it; there is no service to redeploy.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGION="eu-west-1"
TAG="${1:-latest}"
REPO=$(terraform -chdir=terraform output -raw ecr_repository_url)

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform linux/amd64 -t "$REPO:$TAG" .
docker push "$REPO:$TAG"

echo "Pushed $REPO:$TAG"
