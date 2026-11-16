# Decisions

Append-only. Never edit a past entry: supersede it with a new one that links back.

Format:

```
## HD-NNN: Title (YYYY-MM-DD) · Status: proposed | accepted | superseded by HD-MMM
**Context:** what forced the decision
**Decision:** what we chose
**Consequences:** what this makes easier, harder, or rules out
**Revisit when:** the trigger that would reopen it
```

---

## HD-001: Deploy research-agent directly, not wrapped in agent-harness-guide (2026-11-14) · Status: proposed

**Context:** The question was whether research-agent should be wrapped in
agent-harness-guide before deployment. research-agent already vendors and hardens the
guide's `harness.py` (`guards.py`) and builds its 13 principles on the five layers, each with
a test. kagent / Agent Substrate covers sandboxing and part of memory, but not citation
checks, the Distiller or model budgets (`docs/assessment.md`).

**Decision:** Deploy research-agent as its own image implementing kagent's A2A contract. Keep
all its in-process guardrails. Use the guide only as a reference and test pattern.

**Consequences:** research-agent needs an A2A server, MCP over HTTP, S3 report storage and
OTel export (its Phase 4). Its evals keep applying in the cluster. A declarative kagent
agent over research-agent's MCP tools is ruled out for the portal, because it would drop the
loop's budgets and checks.

**Revisit when:** kagent gains platform features for output verification or model budgets,
or a second agent needs the same guardrails and a shared harness library would pay off.

## HD-002: kagent UI is the portal; users from IAM Identity Center (2026-11-14) · Status: accepted

**Context:** Your answers on 2026-11-14.

**Decision:** Use kagent's UI as the portal and IAM Identity Center as the user directory.

**Consequences:** Routing between agents is the user's choice in kagent's UI; no custom front
end. kagent needs OIDC, which Identity Center doesn't offer for custom apps, so an OIDC
broker is needed (open decision, H-002).

**Revisit when:** users need a single entry point that picks the agent for them, or branding
the UI matters.

## HD-003: Where the hub's pieces live, and how agents get secrets (2026-11-16) · Status: accepted

**Context:** The EKS cluster `openbao-nonprod` already runs, built by Terraform in
`openbao-platform`, with Argo CD as an EKS managed capability that may change only the
`kagent`, `agents` and `genai` namespaces and pulls only public `github.com/edwardpius/*`
repos (its D-21). OpenBao and External Secrets run there; Cognito already has a `kagent`
client federated with IAM Identity Center. Your answers, 2026-11-16: the platform pieces go
in a new openbao-platform layer; agent manifests in a new public `ai-hub` repo; a long-term
Bedrock API key with a 90-day expiry; secrets in OpenBao `kv/projects`; RDS PostgreSQL;
web access through a tools pod.

**Decision:**
- openbao-platform layer `45-agent-substrate` installs kagent 1.0 and Agent Substrate 1.0
  (Helm, pinned together), PostgreSQL on RDS, the S3 snapshot bucket (Pod Identity for
  `atelet` and `ate-api-server`), ECR, and the Bedrock key's IAM user; it also creates the
  Argo CD Application `ai-hub`. Layer 30 moves workloads nodes to t3.xlarge; layer 40 labels
  `kagent` for the Substrate API; layer 50 adds the `eso-agents` role and stores the key.
- This repo's `deploy/` holds only namespaced objects Argo CD may sync: SecretStores and
  ExternalSecrets, the research-agent Harness, AgentTemplate, Agent and EgressPolicy, the
  research-tools Deployment, Service, NetworkPolicy and RemoteMCPServer.
- Agents never hold credentials: the egress gateway injects the Bedrock key; search keys
  sit with research-tools.

**Consequences:** The hub is rebuilt by `openbao-platform/scripts/stack.sh up`, which now
needs the `kubectl-ate` plugin. Substrate's database link is encrypted but not verified
(Substrate 1.0 can't mount the RDS CA); kagent's is verified. Images are pinned by digest
through `scripts/release-research-agent.sh`. Sign-in through Cognito (oauth2-proxy and
kagent's trusted-proxy auth) is the next step (H-002); until then the UI is reached by
port-forward.

**Revisit when:** a second cluster or environment is added (the platform layer would move
to its own repo), or kagent supports IAM roles for actors.

## HD-004: Observability with self-hosted Phoenix; the whole hub rebuilds from code (2026-11-16) · Status: accepted

**Context:** Traces exist (research-agent JSONL, kagent and Agent Substrate OpenTelemetry)
but go nowhere. A second agent is planned: a secret tool (create / search) on OpenBao.
Your decisions, 2026-11-16: full content in traces; all sources (research-agent, research-
tools, kagent, Agent Substrate, and future agents); Arize Phoenix deployed in the EKS
cluster; and everything must tear down and spin back up like the OpenBao platform.

**Decision:**
- Phoenix (self-hosted) in the cluster, behind an OpenTelemetry Collector that every source
  sends to over OTLP. Agents emit OpenInference spans (agent, LLM, tool, guardrail).
- Full content capture: prompts, queries, fetched page text and answers are exported to
  Phoenix, which stays inside the VPC behind Cognito sign-in, with a retention period.
- `scripts/stack.sh up` rebuilds the hub with no manual step beyond those it already prints;
  `down` (and `up --restore`) keep what must survive. Each new piece states its lifecycle.

**Consequences:** Phoenix holds user content: access is limited to signed-in admins and
retention is bounded. The Secret MCP agent's traces must never carry secret values (D-19
already forbids values in its tools). research-agent's spec 027 is rewritten around this.

**Revisit when:** a hosted backend (Arize AX) is wanted: only the Collector's exporter changes.
