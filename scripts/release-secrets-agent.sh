#!/usr/bin/env bash
# Build secrets-agent's MCP server for the cluster's x86 nodes, push it to ECR, and pin
# the pushed digest in deploy/agents/secrets-mcp.yaml.
#
#   scripts/release-secrets-agent.sh [path/to/secrets-agent]
#
# Then review the diff, commit and push: Argo CD syncs deploy/.
set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$HUB/../secrets-agent}"
REGION="${AWS_REGION:-us-west-2}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REPO="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/secrets-agent"
TAG="$(git -C "$SRC" rev-parse --short HEAD)-$(date -u +%Y%m%d%H%M%S)"

aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com" >/dev/null

docker buildx build --platform linux/amd64 -t "$REPO:$TAG" --provenance=false --push "$SRC"
DIGEST="$(aws ecr describe-images --region "$REGION" --repository-name secrets-agent \
  --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text)"
[[ "$DIGEST" == sha256:* ]] || { echo "could not read the pushed digest" >&2; exit 1; }

f="$HUB/deploy/agents/secrets-mcp.yaml"
sed -E -i.bak "s#(/secrets-agent@)sha256:[A-Za-z0-9_]+#\1$DIGEST#" "$f" && rm -f "$f.bak"
echo "pushed $REPO:$TAG"
echo "pinned $DIGEST in deploy/agents/secrets-mcp.yaml"

# The secrets-sync reconciler (spec 004) runs the same image from openbao-platform layer 60
# (local, gitignored tfvars). Pin it there too; it takes effect on the next layer 60 apply
# (stack.sh up applies it).
TFVARS="${OPENBAO_PLATFORM:-$HOME/openbao}/infra/60-sync/terraform.tfvars"
if [ -f "$TFVARS" ] && grep -q '^apps_sync_image' "$TFVARS"; then
  sed -E -i.bak "s#(apps_sync_image = \"[^\"]*/secrets-agent@)sha256:[A-Za-z0-9_]+#\1$DIGEST#" "$TFVARS" && rm -f "$TFVARS.bak"
  echo "pinned $DIGEST in $TFVARS (apply layer 60 to roll the reconciler)"
fi
