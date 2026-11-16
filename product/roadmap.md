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
