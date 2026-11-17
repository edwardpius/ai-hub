# Operating Edward's AI Hub

State as of 2026-11-17. Platform code: `~/openbao` (repo openbao-platform, branch
`agent-substrate`). Agent manifests: this repo (`deploy/`), synced by Argo CD. Agent code:
`~/ai_work/agent_harness/research-agent` (branch `phase4-hub`).

## Start it (e.g. the next morning)

1. Sign in to AWS (the SSO session lasts about 8 hours):
   ```bash
   aws sso login --profile agentgrid
   export AWS_PROFILE=agentgrid
   ```
2. Rebuild everything and restore OpenBao's secrets (search keys included) from the last
   teardown snapshot. Takes about 40–50 minutes:
   ```bash
   cd ~/openbao
   scripts/stack.sh up --restore --yes
   ```
   It ends with `research-agent Ready=True` and prints the access commands below. If it
   stops (for example an expired SSO session), sign in again and re-run the same command:
   every finished layer is a no-op.
3. If it prints **ACTION REQUIRED**, follow it. The usual one: search keys missing (only
   after a plain `up` without `--restore`): put `EXA_API_KEY`, `BRAVE_API_KEY`,
   `ADS_API_TOKEN`, `S2_API_KEY` at OpenBao `kv/projects/research-agent/search`.

Prerequisites on the laptop: terraform ≥ 1.10, AWS CLI v2, kubectl, the `kubectl-ate`
plugin (see `~/openbao/infra/45-agent-substrate/README.md`), jq, openssl, curl, python3.

## Use it

| What | Command | Then |
|---|---|---|
| kagent UI (agents) | `kubectl -n kagent port-forward svc/kagent-oauth2-proxy 4180:4180` | http://localhost:4180, sign in with Identity Center |
| Sign out of kagent | (no button in kagent 1.0) | open the `kagent sign-out` link `stack.sh up` prints, or `terraform -chdir=~/openbao/infra/45-agent-substrate output -raw kagent_sign_out_url` |
| Phoenix (traces) | `kubectl -n observability port-forward svc/phoenix 6006:6006` | http://localhost:6006, Identity Center admins only. Projects: `research-agent`, `research-tools`, `platform` (kagent, Agent Substrate) |
| OpenBao UI | `~/openbao/scripts/port-forward.sh` | https://localhost:8200/ui |
| Argo CD | printed by `stack.sh up` | Identity Center sign-in |
| MCP Inspector on the research tools | `kubectl -n agents port-forward svc/research-tools 8080:8080` | Streamable HTTP, http://localhost:8080/mcp |

Only one process can hold a local port: stop an old port-forward before starting a new one
(`lsof -nP -iTCP:4180 -sTCP:LISTEN` shows who has it).

## Stop it (e.g. every evening)

```bash
aws sso login --profile agentgrid   # if the session expired
export AWS_PROFILE=agentgrid
cd ~/openbao
scripts/stack.sh down --yes
```

About 30 minutes. It takes a final OpenBao snapshot, drains the agents, and destroys
everything except the persistent layers: the Terraform state bucket, the KMS key and
OpenBao snapshots, the agent images (ECR), Identity Center and Cognito. **Not kept:**
kagent conversations and Phoenix traces (disposable POC, HD-004). Cost while down: about
$2/month.

`scripts/stack.sh down --all` removes everything, including secrets, images and
identities (it asks you to type the cluster name).

## What runs where

| Piece | Where | Defined in |
|---|---|---|
| EKS `openbao-nonprod`, nodes (1× t3.medium platform, 2× t3.xlarge workloads), network | us-west-2 | openbao-platform layers 10, 30 |
| OpenBao, External Secrets, Argo CD RBAC, namespaces | `openbao`, `external-secrets`, … | layer 40 |
| kagent 1.0 + Agent Substrate 1.0, RDS PostgreSQL, S3 snapshots, Bedrock key, oauth2-proxy, Phoenix + OTel Collector | `kagent`, `ate-system`, `observability` | layer 45 |
| Agent images | ECR `research-agent` (persistent) | layer 05 |
| OpenBao policies, ESO role for agents, Bedrock key in OpenBao | | layer 50 |
| research-agent (kagent bring-your-own agent), research-tools service | `kagent`, `agents` | this repo, `deploy/` (Argo CD) |

Model: Claude Opus 4.6 on Bedrock (`us.anthropic.claude-opus-4-6-v1`) until Bedrock serves
Opus 5.5 to the account (research-agent D-035). To switch: the Harness env
`RESEARCH_AGENT_MODEL` here, and `bedrock_model` in layer 45.

## Release a new research-agent image

```bash
cd ~/ai_work/agent_harness/ai-hub
AWS_PROFILE=agentgrid scripts/release-research-agent.sh ../research-agent
git commit -am "Pin research-agent image <tag>" && git push   # Argo CD syncs it
```

## Cost (us-west-2, on-demand, AWS price list 2026-11-16)

Running 24/7:

| Item | Size | $/month |
|---|---|---|
| EC2 workloads nodes | 2 × t3.xlarge | 242.94 |
| EKS control plane | 1 cluster | 73.00 |
| NAT gateway, its public IP, data | 1 | ~38.50 |
| EC2 platform node (OpenBao) | 1 × t3.medium | 30.37 |
| Argo CD managed capability | 1 + 2 Applications | 23.12 |
| RDS PostgreSQL | db.t4g.micro, 20 GB | 13.98 |
| EBS (node disks, OpenBao, Phoenix) | ~90 GB gp3 | 7.20 |
| CloudWatch logs (EKS audit, API) | estimate | ~5 |
| S3, ECR, KMS, Secrets Manager, Cognito, Lambda | small | ~3 |
| **Total** | | **≈ $437/month** |

Usage: about **$0.15–0.20 per research question** (Claude Opus 4.6, measured $0.14 and
$0.19 at Anthropic list prices; check Bedrock's Marketplace rate on the bill) plus at most
~$0.04 of search. 100 questions a month ≈ $20; 1,000 ≈ $200. Opus 5.5 is ~20% cheaper per
token.

Levers:
- **Run it only when used.** Business hours (8 h × 22 days) ≈ **$107/month** plus usage;
  stopped ≈ $2/month.
- The workloads nodes are 55% of the bill: Spot (−60–70%, fine for a POC), or 2 × t3.large
  (−$120) once utilization is measured, or Graviton t4g (−20%, needs arm64 images).

## Known gaps and next steps

- **Hands-free?** `down` ran unattended on 2026-11-17 (its finalizer retry fired as
  designed). The last `up` needed a re-run after an expired SSO session and one fix
  (found by the 2026-11-16 test, see openbao-platform DECISIONS.md D-23 findings); the next
  start confirms `up` unattended.
- Claude Opus 5.5 on Bedrock: still refused for this account; revisit.
- research-agent specs 026 (S3 report files + download service) and the golden-set evals
  on the hub (to tick the Phase 4 roadmap boxes).
- Sign-in on a real hostname (ingress with TLS, new callback URLs, `cookie-secure` on).
- Next agent: the Secret MCP tool (create / search) on OpenBao, D-19. Its traces reach
  Phoenix through the Collector; its manifests go in `deploy/`, its image repository in
  layer 05 `agent_repositories`.
