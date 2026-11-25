# Operating Edward's AI Hub

State as of 2026-11-24. Platform code: `~/openbao` (repo openbao-platform, branch
`agent-substrate`). Agent manifests: this repo (`deploy/`), synced by Argo CD. Agent code:
`~/ai_work/agent_harness/research-agent` (branch `phase4-hub`).

## From anywhere: Slack, Claude or GitHub (no laptop)

Since 2026-11-24 the hub can be started, stopped and opened to a new address without the
laptop or an AWS sign-in (design and threat model:
[remote-stack-control.md](remote-stack-control.md); openbao-platform D-30 to D-34). The
work runs in GitHub Actions in openbao-platform, with no stored AWS keys. Three front
doors, same actions:

| I want to… | Slack (any client, app.slack.com too) | Claude (claude.ai connector **AI Hub**) | GitHub (fallback) |
|---|---|---|---|
| See if it's up, cost so far, recent runs | `/hub status` | "Is the AI Hub up?" | Actions tab |
| Start it (≈ 50 min, OpenBao restored) | `/hub up` (`up norestore` to skip the restore) | "Start the AI Hub" | Actions → **stack** → Run workflow → `up` |
| Stop it (≈ 30 min, snapshot first) | `/hub down`, then click **Shut down** within 5 min | "Shut the hub down", then confirm | Actions → **stack** → `down` |
| See the allowed addresses | `/hub ips` | "Show the allowed IPs" | – |
| Allow the device I'm on | `/hub allow-me hotel 3d` | "Give me an allow-me link labelled hotel for 3 days" | – |
| Remove an address | `/hub revoke hotel` | "Revoke hotel" | – |
| Find out why a run failed | the **log** link in the DM | "Why did the last run fail?" (reads the log, secrets redacted) | the run's log |

- **Where to type `/hub`:** in any conversation except the hub-control DM, which is
  read-only. Your own DM works well. Replies are visible only to you.
- **Run messages and reminders** arrive in the hub-control DM: started, then finished,
  with the public URLs, or ACTION REQUIRED. Runs started from Claude report there too.
  After 5 hours up you get one reminder. The budget alerts ($100/month, at 50/80/100 %)
  come the same way. Nothing ever starts or stops on its own.
- **An allow-me link** is valid for 10 minutes and works once. Open it on the device or
  network to allow, press **Sign in and allow**, and sign in with Identity Center (MFA).
  The address it records must be IPv4 and must be the same after sign-in. On a phone
  hotspot, the laptop's address is the phone's. If the stack is up, it starts an
  **access** run (about 3 minutes); if it's down, the next `up` uses the address.
  Durations are like `12h` or `3d` (max 30 days), or `permanent`; the default is 24 h.
- **Limits:** at most 6 runs started per hour. One run at a time (a second waits). `down
  --all` and changes to the control plane itself (layer 02) only run from the laptop.
- **Claude connector:** set up once (done 2026-11-24); see
  [Set up the Claude connector](#set-up-the-claude-connector-once) below. The sign-in
  lasts 7 days.
- **When something's off:**
  - `/hub` answers "Not allowed": your Slack workspace or member ID isn't in SSM
    `/openbao-platform/tfvars/02-control`.
  - "dispatch failed" or a GitHub error: the GitHub App isn't installed on
    openbao-platform, or it lost Actions read/write.
  - The link page says "IPv6 not supported": open the link on another network; it stays
    valid.
  - "Your address changed": the network gave you a new address during sign-in. Open the
    link again.
  - Claude says the connector needs a sign-in: reconnect it (Customize → your connectors,
    <https://claude.ai/customize/connectors/yours>).
  - Anything else: hub-control's log, `aws logs tail /aws/lambda/hub-control --since 1h`.

### Set up the Claude connector (once)

Done 2026-11-24. Repeat these steps only on a new claude.ai account, or after the Cognito
user pool is re-created (step 5). The run commands are from the laptop, signed in to AWS.

1. **Allow your Cognito user.** The connector accepts only the Cognito `sub`s listed in
   `operator_cognito_subs` in SSM `/openbao-platform/tfvars/02-control`. Your user exists
   in the pool after you've signed in once through Identity Center (to OpenBao, say). List
   the pool's users with their `sub`:
   ```bash
   POOL=$(terraform -chdir=$HOME/openbao/infra/25-cognito output -raw user_pool_id)
   aws cognito-idp list-users --user-pool-id "$POOL" \
     --query "Users[].[Username, Attributes[?Name=='sub'].Value | [0]]" --output text
   ```
   Every user is named `IdentityCenter_<Identity Center user name>`. Pick yours
   (`IdentityCenter_agentgrid`), not the `obao-test-*` test users. Or try step 3 first: a
   refused call logs `mcp refused`, reason `not operator`, with your `sub`
   (`aws logs tail /aws/lambda/hub-control --since 15m | grep "mcp refused"`). Put the `sub`
   into `operator_cognito_subs` (see "Inputs" in the openbao-platform RUNBOOK) and apply
   layer 02 from the laptop (`scripts/stack.sh up` does it).
2. **Add the connector.** In claude.ai open **Customize** (where Plugins and Connectors
   are) and go to the connectors list (direct link:
   <https://claude.ai/customize/connectors>). Select **Add** → **Add custom connector**:
   - Name **AI Hub**, and the URL from
     `terraform -chdir=$HOME/openbao/infra/02-control output -raw connector_url`
     (now `https://fe22p319rg.execute-api.us-west-2.amazonaws.com/mcp`). **Continue**.
   - Authentication: **Sign in now** (or **Sign in when needed**).
   - OAuth client: **Use your own OAuth client**, with the client ID from
     `terraform -chdir=$HOME/openbao/infra/02-control output -raw connector_client_id`.
     Leave the secret empty; it is a public client. If the dialog is all on one screen,
     these are under **Advanced**. Don't pick "Use Claude's published identity" or
     "Register automatically": Cognito supports neither.
   - **Add**. Authentication settings can't be changed afterwards; to change them,
     remove the connector and add it again.
3. **Connect.** If the connector shows **Connect**, click it. The Cognito page hands you
   to the Identity Center portal; sign in as `agentgrid` with MFA, and you land back in
   claude.ai, connected. The sign-in lasts 7 days; after that Claude asks you to
   reconnect.
4. **Use it.** In a chat, click **+**, find **AI Hub** under Connectors (or Plugins) and
   turn it on for that conversation. It belongs to your claude.ai account, so you can use
   it from any browser you sign in to claude.ai with. Check it with "is the AI Hub up?":
   Claude should call `hub_status` and answer up or down. Its tools: `hub_status`,
   `hub_up` (restores by default), `hub_down` (asks you to confirm), `hub_ips`,
   `hub_allow_me_link`, `hub_revoke`, `hub_run_log`.
5. **After the Cognito pool is re-created** (`stack.sh` prints a reminder): your `sub` and
   the client ID both change. Sign in once, repeat step 1 with the new `sub`. Then remove
   the connector (<https://claude.ai/customize/connectors/yours> → select **AI Hub** →
   **⋯** → **Remove**), add it again with the new `connector_client_id` (step 2), and
   connect.

## Start it from the laptop (e.g. the next morning)

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
   It ends with `research-agent Ready=True`, checks the public URLs below answer, and
   prints them. If it
   stops (for example an expired SSO session), sign in again and re-run the same command:
   every finished layer is a no-op.
3. If it prints **ACTION REQUIRED**, follow it. The usual one: search keys missing (only
   after a plain `up` without `--restore`): put `EXA_API_KEY`, `BRAVE_API_KEY`,
   `ADS_API_TOKEN`, `S2_API_KEY` at OpenBao `kv/projects/research-agent/search`.

Prerequisites on the laptop: terraform ≥ 1.10, AWS CLI v2, kubectl, the `kubectl-ate`
plugin (see `~/openbao/infra/45-agent-substrate/README.md`), jq, openssl, curl, python3.

## Use it

| What | URL | Sign-in |
|---|---|---|
| kagent UI (agents) | https://kagent.edwardpius.me | Identity Center |
| Sign out / switch user in kagent | Bottom right: **Sign out** ends the kagent and Cognito sessions (Identity Center keeps you signed in, so Sign in returns as the same user). **Switch user** opens the AWS access portal in a new tab and signs kagent out: in the portal, Sign out (user menu, top right) and close the tab; then Sign in in kagent as the other user. The portal's **AI Hub (kagent)** tile (Applications tab) also opens kagent (openbao-platform D-26) | |
| Phoenix (traces) | https://arize.edwardpius.me | Identity Center admins only. Projects: `research-agent`, `research-tools`, `platform` (kagent, Agent Substrate) |
| OpenBao UI | https://openbao.edwardpius.me/ui | Identity Center (OIDC) |
| OpenBao CLI | `export BAO_ADDR=https://openbao.edwardpius.me` | `bao login -method=oidc` or `-method=aws` |
| Argo CD | printed by `stack.sh up` | Identity Center |
| research-agent from Slack | DM the **research-agent** app, or `@research-agent <question>` in an allowed channel (pick the mention from Slack's list) | Once, through a private sign-in link (Identity Center); lasts 7 days. See [Slack bridge](#slack-bridge) |
| research-agent from claude.ai | A chat with the **Research** connector on (**+** menu): "Use the Research connector: …" | Once, when you add the connector (Identity Center); lasts 7 days. Works from anywhere, no allowlist entry needed. See [Research connector](#research-connector-claudeai) |

The public URLs and the EKS API answer **only from the allowed addresses**: one list in SSM
(`/openbao-platform/access/cidrs`, openbao-platform D-30). From anywhere else the browser
(and kubectl) times out. Away from the laptop, use `/hub allow-me` or the Claude connector
([From anywhere](#from-anywhere-slack-claude-or-github-no-laptop)). From `~/openbao`:

```bash
scripts/stack.sh ips                              # what's allowed, and until when
scripts/stack.sh allow me hotel --hours 24        # this machine's address, for a day
scripts/stack.sh allow 203.0.113.7/32 office      # a given address, permanent
scripts/stack.sh revoke hotel
```

`allow`/`revoke` apply it at once when the stack is up (layers 30 and 40, a few minutes);
when it's down, the next `up` uses it. Check your current address with
`curl -s https://checkip.amazonaws.com`.

Fallback when the URLs aren't reachable (port-forwards through the Kubernetes API):

| What | Command | Then |
|---|---|---|
| OpenBao UI | `~/openbao/scripts/port-forward.sh` | https://localhost:8200/ui |
| MCP Inspector on the research tools | `kubectl -n agents port-forward svc/research-tools 8080:8080` | Streamable HTTP, http://localhost:8080/mcp |

kagent and Phoenix have no working port-forward fallback while the public endpoints are
on: their sign-in now uses HTTPS-only (Secure) cookies and returns to the public host. If
you're away from the allowed addresses, add your address to `public_access_cidrs` instead.

**`i/o timeout` on the EKS API (in `up`, or from kubectl)?** Your public address changed
(the home connection hands out a new 172.56.x address now and then; found 2026-11-18). The
EKS API no longer lets you in to fix it from kubectl, but `allow` only needs AWS:
`scripts/stack.sh allow me home-lte` (replaces the entry with that label), then re-run
`stack.sh up --restore --yes` if it was interrupted.

**Unauthorized from kubectl?** Your kubeconfig uses the `agentgrid` profile: sign in again
(`aws sso login --profile agentgrid`). Every identity that may run `stack.sh` or kubectl
must be in `cluster_admin_principals` (`~/openbao/infra/30-eks/terraform.tfvars`).

Only one process can hold a local port: stop an old port-forward before starting a new one
(`lsof -nP -iTCP:4180 -sTCP:LISTEN` shows who has it).

## Stop it from the laptop (e.g. every evening)

```bash
aws sso login --profile agentgrid   # if the session expired
export AWS_PROFILE=agentgrid
cd ~/openbao
scripts/stack.sh down --yes
```

About 30 minutes. It takes a final OpenBao snapshot, removes the public endpoints (the
ALB and its DNS records), drains the agents, and destroys
everything except the persistent layers: the Terraform state bucket, the KMS key and
OpenBao snapshots, the agent images (ECR), the TLS certificate, Identity Center and
Cognito, and the AWS Secrets Manager copies of `apps/` secrets (resynced after `up`).
**Not kept:**
kagent conversations and Phoenix traces (disposable POC, HD-004). Cost while down: about
$2.50/month.

`scripts/stack.sh down --all` removes everything, including secrets, images and
identities (it asks you to type the cluster name).

**Inspecting agents on Agent Substrate** (actors per chat session, templates, workers,
suspend/resume, logs): [agent-substrate.md](agent-substrate.md).

## What runs where

| Piece | Where | Defined in |
|---|---|---|
| EKS `openbao-nonprod`, nodes (1× t3.medium platform, 2× t3.xlarge workloads), network | us-west-2 | openbao-platform layers 10, 30 |
| OpenBao, External Secrets, Argo CD RBAC, namespaces | `openbao`, `external-secrets`, … | layer 40 |
| kagent 1.0 + Agent Substrate 1.0, RDS PostgreSQL, S3 snapshots, Bedrock key, oauth2-proxy, Phoenix + OTel Collector | `kagent`, `ate-system`, `observability` | layer 45 |
| Public endpoints: ALB (Gateway API, AWS Load Balancer Controller), ExternalDNS, OpenBao route | `gateway`, `kube-system`, `openbao` | layer 40 (`gateway.tf`) |
| kagent and Phoenix routes | `kagent`, `observability` | layer 45 (`gateway.tf`) |
| Agent images, TLS certificate `*.edwardpius.me` | ECR `research-agent`, ACM (persistent) | layer 05 |
| OpenBao policies, ESO role for agents, Bedrock key in OpenBao | | layer 50 |
| research-agent (kagent bring-your-own agent), research-tools service, research-reports service | `kagent`, `agents` | this repo, `deploy/` (Argo CD) |
| research-agent reports bucket (persistent), research-reports Pod Identity role, `/reports/` download route on the kagent host | S3; `agents`; `kagent` (sign-out nginx) | openbao-platform layers 05, 45 (research-agent spec 026) |
| secrets-agent (kagent runtime on Agent Substrate), secrets-mcp server; OpenBao `apps/` mount | `kagent`, `agents`; OpenBao | this repo, `deploy/` (Argo CD); code in `../secrets-agent`; mount and policies in openbao-platform layer 50 (D-25) |
| Slack bridge (Socket Mode, account linking, A2A through oauth2-proxy); users' refresh tokens in OpenBao `slack-links/` | `agents`; OpenBao | this repo, `deploy/agents/slack-bridge.yaml` (Argo CD); code in `../slack-bridge`; Cognito client, routes, mount and policy in openbao-platform layers 25, 45, 50 (D-28, D-29) |
| Research connector for claude.ai: research-mcp (MCP, OAuth front, A2A through oauth2-proxy) on its own ALB `research.edwardpius.me` | `agents`; Gateway `gateway/connector` | this repo, `deploy/agents/research-mcp.yaml` (Argo CD); code in `../research-mcp`; Cognito client, oauth2-proxy audience, connector ALB, ECR, OpenBao settings in openbao-platform layers 05, 25, 40, 45, 50 (D-35) |
| Remote control (persistent): hub-control Lambda (Slack `/hub`, Claude connector, allow-me links, run DMs, reminder, budget alerts), its IPv4 API Gateway, DynamoDB table, two Secrets Manager secrets; GitHub Actions role `hub-deployer`; budget `ai-hub-monthly` | us-west-2; workflows in openbao-platform `.github/workflows` | openbao-platform layer 02 (D-31 to D-34), applied only from the laptop |
| secrets-sync reconciler + ESO stores: `apps/` secrets with AWS sync on -> Secrets Manager `openbao/...` | `secrets-sync` | openbao-platform layer 60 `apps_sync.tf` (D-27); image pinned in its local `terraform.tfvars` |

Model: Claude Opus 4.6 on Bedrock (`us.anthropic.claude-opus-4-6-v1`) until Bedrock serves
Opus 5.5 to the account (research-agent D-035). To switch: the Harness env
`RESEARCH_AGENT_MODEL` here, and `bedrock_model` in layer 45.

## Release a new agent image

`scripts/release-secrets-agent.sh ../secrets-agent` works the same way as the research-agent
one below (pins `deploy/agents/secrets-mcp.yaml`). It also pins the secrets-sync reconciler
in `~/openbao/infra/60-sync/terraform.tfvars`; roll that with
`terraform -chdir=$HOME/openbao/infra/60-sync apply -var-file=../common.tfvars` (or the next
`stack.sh up`).

## research-agent's report key (once, ever)

Reports are stored under an HMAC of each user's ID (research-agent spec 026). Before the
first `up` with the reports service, put the key in OpenBao; `stack.sh up` reminds you if
it's missing, and `up --restore` brings it back after a teardown:

```bash
bao kv put kv/projects/research-agent/reports USER_HASH_KEY="$(openssl rand -hex 32)"
```

Never replace it: a new key hides every earlier report from its owner (the files stay in
S3, readable by admins).

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
| Secrets Manager copies of `apps/` secrets (kept while down) | $0.40 per secret | ~1 per 2–3 secrets |
| **Platform subtotal** | | **≈ $437** |
| Public endpoints: ALB | 1, light traffic (LCU ~$1) | ~17.40 |
| Public endpoints: ALB's public IPv4 addresses | 2 (one per AZ) | 7.30 |
| Research connector ALB (HD-008), its 2 IPv4 addresses | 1, light traffic | ~24.70 |
| Route 53 hosted zone `edwardpius.me` | 1 (existed before) | 0.50 |
| **Total** | | **≈ $487/month** |

Usage: about **$0.15–0.20 per research question** (Claude Opus 4.6, measured $0.14 and
$0.19 at Anthropic list prices; check Bedrock's Marketplace rate on the bill) plus at most
~$0.04 of search. 100 questions a month ≈ $20; 1,000 ≈ $200. Opus 5.5 is ~20% cheaper per
token.

Levers:
- **The remote control plane** (hub-control, its API, table, schedule, two secrets, the
  budget topic) costs about $1–2/month and stays while the hub is down. The budget
  `ai-hub-monthly` ($100, account-wide) alerts in Slack at 50/80/100 % and on the forecast.
- **Run it only when used.** Business hours (8 h × 22 days) ≈ **$113/month** plus usage
  (the public endpoints add about $6 of that, the Research connector ALB about $6 more);
  stopped ≈ $2.50/month.
- The workloads nodes are 55% of the bill: Spot (−60–70%, fine for a POC), or 2 × t3.large
  (−$120) once utilization is measured, or Graviton t4g (−20%, needs arm64 images).

## Slack bridge

Ask research-agent from Slack (HD-006, spec H-006, plan and setup in
[slack-integration.md](slack-integration.md)). The bridge runs as the user who asks: each
Slack user links their hub account once. It answers DMs, and mentions in the channels on
its allowlist. It posts a summary and the full report as a file in the thread.

- **Tokens and channels** live in OpenBao at `kv/projects/slack-bridge/slack`
  (`SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `ALLOWED_CHANNELS`). They survive `down`, and
  `up --restore` brings them back. `stack.sh up` reminds you if they're missing. To allow
  another channel, invite the bot there, then:

  ```bash
  bao kv patch kv/projects/slack-bridge/slack ALLOWED_CHANNELS=C0AAA,C0BBB
  kubectl -n agents annotate externalsecret slack-bridge force-sync=$(date +%s) --overwrite
  kubectl -n agents rollout restart deploy/slack-bridge
  ```

- **Links:** a user's link lasts 7 days (the bridge client's refresh token), and they're
  asked to sign in again after that. `disconnect` in a DM revokes and deletes a link.
  Admins can list and delete links but can't read them:
  `bao kv metadata delete slack-links/<team ID>/<user ID>`. Signing in works only from the
  allowed addresses, like the kagent UI.
- **Logs:** `kubectl -n agents logs deploy/slack-bridge`. There's one line per event: its
  kind, outcome (`link_offered`, `completed`, `disconnect`, `error`, …) and a reference.
  The reference is the one an error message in Slack shows. Mentions in channels that
  aren't allowed are logged as `ignored`. If nothing is logged, Slack didn't send the event,
  usually because the mention was typed as plain text.
- **Slack or the bridge down:** the kagent UI is unaffected (EVAL-07). Messages sent to the
  bot while it's down are dropped by Slack, not answered later: ask again. Runs started from Slack show there
  under the same user (EVAL-02, verified 2026-11-19).
- **Release:** `AWS_PROFILE=agentgrid scripts/release-slack-bridge.sh ../slack-bridge`.
  It runs the bridge's tests and pins `deploy/agents/slack-bridge.yaml`; commit and push.

## Research connector (claude.ai)

Ask research-agent from a Claude chat (HD-007, HD-008, spec H-007). claude.ai calls
`https://research.edwardpius.me/mcp` from Anthropic's servers; research-mcp starts the run
**as you**, with your own ID token, through kagent's oauth2-proxy, the same path as the
Slack bridge. Runs and reports show in the kagent UI under the same user.

**Set it up (once per claude.ai account; done 2026-11-25):**
1. claude.ai → **Customize** → Connectors (<https://claude.ai/customize/connectors>) →
   **Add** → **Add custom connector**. Name **Research**, URL
   `https://research.edwardpius.me/mcp`, **Continue**.
2. Authentication **Sign in now**; OAuth client **Use your own OAuth client**, client ID
   from `terraform -chdir=$HOME/openbao/infra/25-cognito output -raw research_mcp_client_id`,
   secret empty (public client). **Add**, then **Connect** and sign in through Identity
   Center (MFA).

**Use it:** in a chat, **+** → turn **Research** on, then ask, for example: "Use the
Research connector: call research_start with this question, then research_result until
it's done: …". Claude starts the run, then polls: `research_result` waits up to 45 s and
says "still running" until the report is ready (usually 1–3 minutes, about $0.30). Also
`research_status`, `list_my_reports` (runs started from Claude in the last 24 hours) and
`get_report` (any of your reports, by its link).

- **Limits:** one run at a time per user, 20 a day, 10 minutes a run. Anyone assigned to
  the app in Identity Center can use it, each seeing only their own runs.
- **Only while the hub is up.** When it's down, the connector can't be reached; the
  **AI Hub** connector's `hub_status` says so, and `hub_up` starts it.
- **No allowlist needed:** the connector has its own ALB that admits Anthropic's ranges
  (`160.79.104.0/21`, `153.61.208.0/20`) plus the allowlist (your browser signs in through
  it). The hub ALB never admits Anthropic's ranges.
- **Logs:** `kubectl -n agents logs deploy/research-mcp`. One line per tool call (`mcp tool`,
  hashed user, outcome, caller IP), per run (`run started`, `run finished` with seconds),
  and per refusal (`mcp refused` with the reason). Error messages in Claude carry a
  reference that matches a log line. No tokens, questions or reports are logged.
- **"Bad Gateway" in Claude:** a call held open past 60 s (the ALB's idle timeout). The
  server holds 45 s, so this means something is slow; check the log.
- **Sign-in problems:** reconnect in Customize → Connectors → Research. After the Cognito
  pool is re-created (`stack.sh up` reminds you): the client ID changes. Remove the
  connector and add it again with the new ID, and restart the pod so it reads the new
  settings: `kubectl -n agents rollout restart deploy/research-mcp`.
- **Release:** `AWS_PROFILE=agentgrid scripts/release-research-mcp.sh ../research-mcp`.
  It runs the server's tests and pins `deploy/agents/research-mcp.yaml`; scan with Trivy,
  commit and push.

## Known gaps and next steps

- **oauth2-proxy logs the Slack sign-in callback URL with its one-time code.** The code is
  used within a second and is useless without the bridge's PKCE verifier, but it shouldn't
  be logged. The fix is to exclude the path from request logging (layer 45).
- H-006: all evals passed (EVAL-01 and EVAL-04 on 2026-11-20); results are on the roadmap line.
- H-007 (Research connector): `list_my_reports` only knows runs started from Claude in the
  last 24 hours; a list endpoint in research-agent's reports service would cover all of
  them. EVAL-07 (hub down) is checked at the next `down`.

- **Hands-free?** `down` ran unattended on 2026-11-17 (its finalizer retry fired as
  designed). The last `up` needed a re-run after an expired SSO session and one fix
  (found by the 2026-11-16 test, see openbao-platform DECISIONS.md D-23 findings); the next
  start confirms `up` unattended.
- Claude Opus 5.5 on Bedrock: still refused for this account; revisit.
- research-agent specs 026 (S3 report files + download service) and the golden-set evals
  on the hub (to tick the Phase 4 roadmap boxes).
- Next agent: the Secret MCP tool (create / search) on OpenBao, D-19. Its traces reach
  Phoenix through the Collector; its manifests go in `deploy/`, its image repository in
  layer 05 `agent_repositories`.
