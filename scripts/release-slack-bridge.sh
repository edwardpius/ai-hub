#!/usr/bin/env bash
# Build slack-bridge for the cluster's x86 nodes, push it to ECR (repo from openbao-platform
# layer 05), and pin the pushed digest in deploy/agents/slack-bridge.yaml.
#
#   scripts/release-slack-bridge.sh [path/to/slack-bridge]
#
# Runs the bridge's offline tests first. Then review the diff, commit and push: Argo CD
# (ai-hub-agents) syncs deploy/agents/.
set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$HUB/../slack-bridge}"
REGION="${AWS_REGION:-us-west-2}"

[ -z "$(git -C "$SRC" status --porcelain)" ] || { echo "$SRC has uncommitted changes" >&2; exit 1; }
(cd "$SRC" && uv run --frozen pytest -q)

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REPO="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/slack-bridge"
TAG="$(git -C "$SRC" rev-parse --short HEAD)-$(date -u +%Y%m%d%H%M%S)"

aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com" >/dev/null

docker buildx build --platform linux/amd64 -t "$REPO:$TAG" --provenance=false --push "$SRC"
DIGEST="$(aws ecr describe-images --region "$REGION" --repository-name slack-bridge \
  --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text)"
[[ "$DIGEST" == sha256:* ]] || { echo "could not read the pushed digest" >&2; exit 1; }

f="$HUB/deploy/agents/slack-bridge.yaml"
sed -E -i.bak "s#/slack-bridge@sha256:[A-Za-z0-9_]+#/slack-bridge@$DIGEST#" "$f" && rm -f "$f.bak"
grep -q "/slack-bridge@$DIGEST" "$f" || { echo "could not pin the digest in $f" >&2; exit 1; }
echo "pushed $REPO:$TAG"
echo "pinned $DIGEST in deploy/agents/slack-bridge.yaml"
