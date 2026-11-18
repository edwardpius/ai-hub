#!/usr/bin/env bash
# Build research-agent for the cluster's x86 nodes, push it to ECR, and pin the pushed
# digest in the manifests (kagent rejects a Harness image named by tag only).
#
#   scripts/release-research-agent.sh [path/to/research-agent]
#
# Then review the diff, commit and push: Argo CD syncs deploy/ (Application "ai-hub").
set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$HUB/../research-agent}"
REGION="${AWS_REGION:-us-west-2}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REPO="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/research-agent"
# Immutable tags: the commit, plus a timestamp so a rebuild of the same commit gets its own.
TAG="$(git -C "$SRC" rev-parse --short HEAD)-$(date -u +%Y%m%d%H%M%S)"

aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com" >/dev/null

docker buildx build --platform linux/amd64 -t "$REPO:$TAG" --provenance=false --push "$SRC"
DIGEST="$(aws ecr describe-images --region "$REGION" --repository-name research-agent \
  --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text)"
[[ "$DIGEST" == sha256:* ]] || { echo "could not read the pushed digest" >&2; exit 1; }

for f in "$HUB/deploy/kagent/research-agent.yaml" "$HUB/deploy/agents/research-tools.yaml" \
         "$HUB/deploy/agents/research-reports.yaml"; do
  sed -E -i.bak "s#(/research-agent@)sha256:[A-Za-z0-9_]+#\1$DIGEST#" "$f" && rm -f "$f.bak"
done
echo "pushed $REPO:$TAG"
echo "pinned $DIGEST in deploy/; scan results: aws ecr describe-image-scan-findings --repository-name research-agent --image-id imageDigest=$DIGEST"
