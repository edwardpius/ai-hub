# Tech stack

**Status: PROPOSED 2026-11-14.** Rows move from Open decisions to Stack as decisions are
recorded in `decisions.md`.

## Platform principles

Every agent and tool server on the hub must meet these. An agent's own spec says how it
does; it never restates them.

1. **GitOps only.** Every cluster change is a commit that ArgoCD applies. No `kubectl apply`
   outside development.
2. **Pinned together.** kagent, Agent Substrate and agentgateway versions are pinned in Git
   and upgraded as one change, with a migration note. (kagent 1.0 has no in-place upgrade path.)
3. **Sandboxed by default.** Every agent runs as a Substrate actor in at least a gVisor
   sandbox. No privileged pods, no host Docker socket.
4. **No credentials in sandboxes.** API keys are added by agentgateway on egress; AWS access
   comes from a workload identity scoped to the minimum actions.
5. **Internal by default.** Only the kagent UI and its A2A endpoint are reachable from
   outside, behind sign-in. MCP servers are ClusterIP services with no Ingress.
6. **Each agent declares its trifecta legs** (private data, untrusted content, outbound) in
   its onboarding spec. agentgateway policy blocks any call path that combines all three
   across agents.
7. **Agents keep their own harness.** The platform's isolation doesn't replace an agent's
   in-process guardrails, budgets and output checks (assessment, HD-001).
8. **Per-user ownership.** Conversations, files and traces are keyed by the signed-in user.
9. **Everything is traced.** Agents export OpenTelemetry to the hub's collector, with
   message content capture off unless a decision says otherwise.
10. **Cost is attributed.** Every model call is attributable to an agent and a user.

## Stack

| Layer | Choice | Version | Why |
|---|---|---|---|
| Cluster | Amazon EKS | pin in H-001 | Your choice; in the cluster repo |
| Delivery | ArgoCD, Helm charts | pin in H-001 | Your choice |
| Agent runtime | kagent with Agent Substrate | 1.0 line, Substrate pinned by kagent | Per-conversation sandboxes, snapshots, A2A, OIDC (assessment) |
| Agent sandbox class | gVisor (default) | — | Default in kagent 1.0; no hypervisor needed |
| Portal | kagent UI | with kagent | Your choice (2026-11-14) |
| User directory | IAM Identity Center | — | Your choice (2026-11-14) |
| Gateway | agentgateway | with kagent | LLM, MCP and A2A traffic policy; key injection |
| State | PostgreSQL (installed by kagent) + S3 for snapshots | — | Required by kagent 1.0 |
| Agent output files | S3, per-user prefix | — | Durable beyond Substrate's 7-day session cleanup |
| First agent | research-agent, own image over A2A | research-agent Phase 4 | Keeps its harness (HD-001) |

## Open decisions

| Decision | Options | Decide when |
|---|---|---|
| OIDC broker for Identity Center | **Cognito user pool with Identity Center as SAML IdP (recommended)** · Dex · Keycloak | H-002, before any user signs in |
| AWS credentials for actors | Pod Identity on worker pods · through agentgateway · a small upload service | H-003; research-agent spec 026 depends on it |
| Model provider path | Anthropic API through agentgateway · Amazon Bedrock with IAM | H-003; research-agent uses the Anthropic API today |
| Sandbox class per pool | gVisor · microvm | When an agent needs a stronger boundary; check EKS node needs (`.metal`?) first |
| Observability backend | kagent's OTel + CloudWatch · Grafana stack · Langfuse | H-005, when the first agent runs |
| Per-user cost caps | none (small known user set) · daily USD cap per user | After a month of cost data per user |
| AWS region and account layout | — | H-001 |
