# Assessment: research-agent on Edward's AI Hub (kagent / Agent Substrate on EKS)

**Date:** 2026-11-14 · **Input:** `jev-prompt` and the follow-up answers in the same session

## The question

- Should `research-agent` be wrapped in `agent-harness-guide` before it is deployed, or deployed
  directly? What is the harness worth?
- How should it run on kagent / Agent Substrate in an EKS cluster managed by ArgoCD, as the
  first agent in a portal called "Edward's AI Hub", with more agents to follow?

## Short answer

**Don't wrap it. research-agent already contains the harness.** Deploy research-agent as its
own agent image on kagent 1.0 / Agent Substrate, and keep its in-process guardrails.

## The two repos

| | agent-harness-guide | research-agent |
|---|---|---|
| What it is | A teaching repo for an article: five guard layers, each shown with the guard on and off, against a scripted fake model | A working research agent that writes cited reports. Roadmap phases 0–3 shipped, 586 offline tests |
| Reusable code | `harness.py`, one file, no dependencies | About 6.5k lines: its own Messages API loop, one `dispatch()` choke point, guards, evals, MCP server, Docker sandbox |
| Interface | Scripts and tests | CLI and MCP over stdio. **No HTTP or A2A endpoint yet** |

`research-agent/src/research_agent/guards.py` is "Adapted from harness.py" and hardened: rules
fail closed, and paths go through `realpath` as well as `normpath`. The 13 principles in
`research-agent/product/tech-stack.md` are the five harness layers, extended with SSRF checks
after every redirect, hard budgets, citation checks and polite fetching. Each has a test that
fails if the guard is removed. Wrapping research-agent in the guide would put a weaker copy
around a stronger one.

The guide stays useful as a **reference and a test pattern** (`shared/fake_agent.py` for
deterministic CI), not as a deployable.

## What the harness is worth on Kubernetes

| Harness layer | kagent / Substrate gives you | Keep in research-agent's code? |
|---|---|---|
| Sandboxing | One gVisor (or microVM) sandbox per session | Yes, workspace path checks as a second layer |
| Network allowlist and secrets | agentgateway: egress policy, keys added outside the sandbox | Yes. The per-redirect SSRF check knows more than the gateway |
| Memory | Session snapshots to object storage, history in Postgres, checkpoint and fork | Partly. Reports need durable storage (Substrate cleans idle sessions after 7 days by default) |
| Verification (citation check, read-only reviewer) | No equivalent | **Yes** |
| Context control and budgets (Distiller, `max_turns`, `max_usd`) | No equivalent | **Yes** |

**The platform controls what the agent can reach. The harness controls what the agent does
with it.** Both are needed.

The last two rows matter because "no equivalent" means nothing else does the job:

- **Citation check.** Substrate can stop the agent reaching your files. It cannot tell
  whether a report says what its sources say. That needs the run's own record of which pages
  were fetched and what each cited sentence claims. It is the agent's main quality control:
  spec 022 took misattributed sentences on the harder set from 4 to 0.
- **Distiller and budgets.** Substrate limits CPU and memory, not model spend. A sandbox can
  sit inside its limits while the agent loops for 40 turns and spends $5. The Distiller keeps
  context small; the budgets stop a run with a typed stop reason. They are what keep the
  median at $0.23–0.32 a question. With many portal users this is the per-user cost control,
  and nothing else in the stack provides it.

## kagent 1.0 and Agent Substrate: what matters here

- kagent 1.0 moves agents from Deployments to **Actors** on Agent Substrate. When a turn
  ends, the actor's memory and filesystem are snapshotted to object storage and its worker
  pod is released. The next message restores it onto any free worker. An operator must
  provision a **WorkerPool** first.
- Every agent runs in a **gVisor** sandbox by default. A `microvm` sandbox class adds a
  hypervisor boundary; the pool selects the class.
- **A2A is always on**, addressed at `/agents/{namespace}/{name}` over HTTP.
- A **Harness** can run your own container image if it implements kagent's A2A contract
  (resources: Harness, AgentTemplate, Agent; CRD group `api.kagent.dev/v1alpha3`).
- **RemoteMCPServer** is the only MCP server kind a tool binding accepts. MCP servers run
  outside kagent; `MCPServer` and kmcp are gone in 1.0.
- Users sign in through **OIDC**. Each conversation belongs to the user who started it.
- **No upgrade path from 0.10.x**, and Agent Substrate must not be upgraded separately from
  kagent. Sources disagree on the exact Substrate version, so pin the charts.

## Recommended deployment shape

Two options were compared:

- **A (recommended): bring your own agent image.** Put an A2A server in front of
  research-agent's existing loop. All guardrails, evals and the trace format stay.
- **B: a declarative kagent agent using research-agent's tools over MCP.** This replaces
  research-agent's loop with kagent's, so budgets, the Distiller and the evals stop applying.
  Only worth it if you want the tools without the agent.

One image, run two ways:

| Workload | Protocol | kagent resource | Used by |
|---|---|---|---|
| research-agent with its tools built in | A2A | Harness + AgentTemplate + Agent (own image) | kagent UI users |
| research tools only | MCP over streamable HTTP | RemoteMCPServer | MCP Inspector during development; other agents later, if chosen |

## Your answers (2026-11-14) and what follows from them

| # | Answer | Consequence |
|---|---|---|
| 1 | Portal is **kagent's UI** | Routing between agents happens in kagent. A TypeSafe/Jev router is not needed for now |
| 2 | Users come from **IAM Identity Center** | kagent needs OIDC; Identity Center signs users into custom apps with SAML 2.0. A broker is needed: **Amazon Cognito user pool** with Identity Center as a SAML provider (recommended), or Dex/Keycloak in the cluster |
| 3 | Reports **in chat and as files** | Return the report text over A2A, and write the `.md` to S3 under a per-user prefix. AWS access through EKS Pod Identity or IRSA, never keys in the pod |
| 4 | `run_python`: unclear | See below. Recommendation: off on the cluster for now |
| 5 | MCP tools **in the cluster, tested with MCP Inspector**, not used from Claude Code | Add streamable HTTP alongside stdio; reach it with `kubectl port-forward`; ClusterIP only, never an Ingress |

### `run_python` explained

A tool that lets the agent run short Python calculations to check numbers from its sources,
for example recomputing a percentage a paper reports. On a Mac it starts a locked-down Docker
container per calculation (spec 020). On the cluster the agent already runs inside a gVisor
sandbox, and Docker cannot be started from inside it, so the tool cannot work as built.

- **Recommended now:** leave it off on the cluster. The agent already hides the tool when
  Docker is missing, so no code change is needed. Expect slightly weaker answers on numeric
  questions; it was used on 3 of 10 golden questions.
- **Later:** rebuild it as a separate calculator service or a restricted sub-process.

### MCP server cautions

- **Internal only.** It is a tool that fetches web pages. Exposed outside the cluster it
  becomes an open proxy that spends your search credits.
- **One session still means one provenance scope.** `fetch_url` only reads URLs a search in
  the same session returned (D-025). Over HTTP, each MCP session needs its own allowlist,
  budgets and trace. Test it.

## Lethal trifecta across agents

research-agent is safe because no tool reads private data while untrusted content and an
outbound channel are always present (principle 10). Once more agents join the hub, a
sub-agent binding or a shared tool can bring the third leg back. The hub needs a platform
rule: **an agent with untrusted content and outbound access may never call, or be called
with results from, an agent that reads private data.** Enforce it in agentgateway policy.

## Where TypeSafe / Jev fits

Jev returns fast, typed yes/no answers, choices and scores with probabilities. With kagent's
UI doing routing, the useful places are inside research-agent:

- **Rank search results before fetching.** Score candidates on relevance and how primary the
  source is, then fetch fewer pages. This cuts cost and time.
- **A cheaper citation judge.** research-agent lists a cheaper judge as an open decision. A
  Noul "does this passage support this sentence?" could pre-screen or replace the Opus judge.
  Validate it against the existing labels with `research-calibrate`.
- **Scope check on input**, enforcing `product/mission.md`'s scope.

TypeSafe would be another outside service, seeing questions and web content only, so it adds
no private data. These are ideas to evaluate on your data, not results.

## Open items to verify

- EKS node requirements for Substrate: the gVisor runtime on nodes, and possibly `.metal`
  instances for the microVM class. Not covered in the kagent pages read.
- How a Substrate actor gets AWS credentials for S3 (worker Pod Identity, or through the
  egress gateway).
- kagent's exact A2A contract for a bring-your-own image (the "Run your own agent image"
  example).
- The research-agent README still says "Nothing is implemented yet", which is out of date.

## Sources

- [Agent Substrate in Production: Announcing kagent 1.0](https://www.solo.io/blog/announcing-kagent-1-0-ga)
- [kagent 1.0 release notes](https://kagent.dev/docs/kagent/latest/reference/release-notes/1.0/)
- [kagent version support](https://kagent.dev/docs/kagent/latest/reference/versions/)
- [kagent GitHub releases](https://github.com/kagent-dev/kagent/releases)
- [IAM Identity Center: customer managed applications](https://docs.aws.amazon.com/singlesignon/latest/userguide/customermanagedapps.html)
- [TypeSafe docs index](https://docs.typesafe.ai/llms.txt)
