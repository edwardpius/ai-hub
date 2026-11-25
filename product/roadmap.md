# Roadmap

This file is the **only** place hub status lives. Agent-side work is tracked in each agent's
own roadmap and linked here, never duplicated.

Effort: `XS` ≈ 1 day · `S` ≈ 2–3 days · `M` ≈ 1 week · `L` ≈ 2 weeks · `XL` ≈ 3+ weeks

Hub specs (`H-NNN`) are written in the cluster repo when it exists.

---

## Phase 0: Cluster foundations

**Goal:** An empty hub that can run a sandboxed agent, built entirely from Git.

**Success criteria:**
- Rebuilding the cluster from the repo reproduces it with no manual steps.
- kagent's sample agent answers in a gVisor sandbox, suspends when idle and resumes.
- No Service of type LoadBalancer or Ingress except the portal's.

- [ ] EKS and ArgoCD - cluster, node groups that can run gVisor, ArgoCD watching the repo, region and account layout `M` → H-001
- [ ] kagent and Agent Substrate - pinned Helm install through ArgoCD, PostgreSQL, S3 snapshot bucket, a WorkerPool, agentgateway with a model route `M` → H-003

## Phase 1: Sign-in

**Goal:** Users from IAM Identity Center sign in to kagent's UI and only see their own
conversations.

**Success criteria:**
- A user assigned in Identity Center signs in; an unassigned user cannot.
- User A cannot open user B's conversation by URL or API.

- [ ] Identity Center sign-in - OIDC broker (Cognito recommended) federated with Identity Center over SAML, kagent UI and A2A behind it `S` → H-002

## Phase 2: research-agent on the hub

**Goal:** A signed-in user asks research-agent a question in the portal and gets the report
in the chat and as a file.

**Depends on:** research-agent Phase 4 (`research-agent/product/roadmap.md`).

**Success criteria:**
- research-agent's golden set run through the portal path meets its own regression bar
  (k=1 at least 8 of 10).
- Median time under 3 minutes and cost under $0.50, as on a laptop.
- Zero safety-invariant violations; the MCP server is unreachable from outside the cluster.

- [ ] Onboard research-agent - Harness, AgentTemplate and Agent for its image; egress policy for its search and fetch hosts; report bucket and workload identity; trifecta legs declared `S` → H-004
- [ ] Research tools over MCP - RemoteMCPServer for the research tools, ClusterIP only, MCP Inspector through port-forward `XS` → H-004

## Phase 3: Operate

**Goal:** See what each agent does and costs, per user.

- [ ] Traces and cost - OTel from agents to the chosen backend, cost per agent and per user, alerts on spend `S` → H-005

## Phase 4: Later

Ideas, not commitments. Each needs a spec first.

- Agent onboarding template: the checklist and manifests a new agent must meet (principles 3–10)
- Cross-agent trifecta policy in agentgateway, needed when the second agent arrives
- Per-user daily cost caps
- A routing agent (for example TypeSafe/Jev) if users start picking the wrong agent

## Phase 5: research-agent from Slack

**Goal:** A signed-in user asks research-agent in a Slack channel or DM and gets the report
in the thread, as the same user as in the kagent UI (HD-006).

**Success criteria:**
- Golden-set questions asked in Slack meet research-agent's bar, median under 3 minutes and
  under $0.50.
- A report asked for in Slack shows up for the same user in the UI; with the bridge stopped,
  the UI still works.
- A user not assigned in Identity Center can't link; an unsigned token is refused.

- [x] Slack bridge - Socket Mode bridge, account linking through its own Cognito client, A2A through oauth2-proxy `M` → H-006 (`specs/H-006-slack-bridge/spec.md`). Live
  2026-11-19: link, DM run, run in the allowed channel, disconnect and link again all
  worked; EVAL-02 (Slack runs under the same user in the kagent UI), EVAL-03 (thread
  follow-up continues the context), EVAL-05 and EVAL-06 (forged tokens refused, 403),
  EVAL-07 (bridge at 0: no Slack reply, kagent UI answered) passed. 2026-11-20: EVAL-01
  (golden set asked in Slack) passed, 10 of 10 (bar 8), median 67 s, median $0.30 a
  question (max $0.41), 0 invariant violations. EVAL-04 (a user not assigned in Identity
  Center can't link and gets no answer) passed. All H-006 evals passed.

## Phase 6: research-agent from claude.ai

**Goal:** A signed-in user asks research-agent from a Claude chat through a custom connector
and gets the cited report, as the same user as in the kagent UI and Slack (HD-007).

**Success criteria:**
- Golden-set questions asked in claude.ai meet research-agent's bar, median under 3 minutes
  and under $0.50.
- A report asked for in claude.ai shows up for the same user in the UI.
- Forged tokens are refused, and nothing but the connector's paths is reachable from
  outside the allowlist.

- [ ] claude.ai connector - remote MCP server in front of research-agent over A2A, Cognito sign-in, start/status/result tools `M` → H-007 (`specs/H-007-claude-connector/spec.md`). Questions answered 2026-11-25; task 2 (oauth2-proxy accepts the new client's ID token) passed 2026-11-25; next: task 3
