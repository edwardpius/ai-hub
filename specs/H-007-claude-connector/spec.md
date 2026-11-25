# H-007 – Ask research-agent from claude.ai

**Roadmap:** Phase 6 / claude.ai connector · **Status:** see `product/roadmap.md` (never here)
**Decision:** HD-007 (proposed) · **Pattern:** H-006 (Slack bridge), openbao-platform D-33
(the AI Hub connector)

Hub specs belong in the cluster repo (README); this one sits here until that repo has a
`specs/` folder.

## Intent

A signed-in hub user adds research-agent to claude.ai as a custom connector, asks it a
question from a Claude chat (web, and wherever else the connector is available), and gets
the cited report back in the chat, as the same user they are in the kagent UI and in Slack.
claude.ai is a third way in, beside the UI and Slack (H-006): the UI keeps working with the
connector down, and all three show the same conversations and reports. This serves the
mission of offering the hub's agents to signed-in users where they already work.

**Out of scope:**
- Other agents (one agent, `kagent/research-agent`).
- Exposing `research-tools` (search and fetch, research-agent spec 024) to claude.ai: Claude
  has its own search; the value is research-agent's loop, citation check and stored report.
- Starting or stopping the hub: that's the **AI Hub** connector (D-33). This connector only
  works while the hub is up.
- Claude Code and the Claude API's MCP connector (same server would work; not tested here).
- Changes to kagent or to research-agent's code.

## Resolved questions

- Resolved 2026-11-25 (Q1, how claude.ai reaches the hub): a **second ALB** with its own
  hostname, `research.<domain>`, admits Anthropic's published outbound ranges
  (`160.79.104.0/21`, and `153.61.208.0/20` from the API IP page) plus your /32s, and has
  only the research-mcp route (HD-008, openbao-platform D-35). The hub ALB is unchanged.
  First answer was a path rule on the kagent host; dropped because the hub ALB's
  allowlist is a security group, which can't scope by path. MCP tunnels were ruled out:
  research preview, Claude Enterprise only.
- Resolved 2026-11-25 (Q2, who): any user assigned to the app in Identity Center, as the UI
  and Slack; identity and per-user isolation come from Cognito and kagent.
- Resolved 2026-11-25 (Q3): yes, `list_my_reports` and `get_report`, read-only, the
  caller's own reports only. Built (task 4): the reports service has no list endpoint
  (research-agent spec 026 serves one report by `/reports/<run>/<name>`), so
  `list_my_reports` lists the runs started from claude.ai in the last 24 hours (server
  memory) and points to the kagent UI for older ones; `get_report` reads any of the
  caller's reports by its link. Follow-up: a list endpoint in the reports service.
- Resolved 2026-11-25 (Q4): its own public repo, `research-mcp`, like `slack-bridge`.

## Requirements

### Sign-in

- **REQ-01** THE SERVER SHALL serve MCP streamable HTTP at `/mcp` on `research.<domain>`
  (the connector ALB), with Protected Resource Metadata (RFC 9728) and authorization-server metadata
  (RFC 8414) at the matching `/.well-known/` paths, and a `WWW-Authenticate` header on 401.
- **REQ-02** THE SERVER SHALL pass `/oauth/authorize` and `/oauth/token`
  through to Cognito for one public PKCE client, `research-mcp-claude`, whose only callback
  is `https://claude.ai/api/mcp/auth_callback`, with Identity Center as the identity
  provider (as D-33).
- **REQ-03** WHEN Cognito returns tokens THE SERVER SHALL give claude.ai Cognito's **ID
  token** as `access_token` (and pass the refresh token through), because oauth2-proxy
  accepts Cognito ID tokens with this client's audience as bearer tokens (H-006). It SHALL
  NOT create, sign or alter a token (as H-006 REQ-17).
- **REQ-04** IF a request to `/mcp` has no bearer token, or one that fails
  signature, `iss`, `aud`, `token_use=id` or expiry checks, THEN THE SERVER SHALL answer 401
  with `WWW-Authenticate` and call nothing.
- **REQ-05** The refresh-token lifetime of `research-mcp-claude` SHALL be 7 days (as H-006
  REQ-07 and D-33), which bounds how long a removed user keeps access.

### Asking

- **REQ-06** WHEN `research_start` is called THE SERVER SHALL start a research-agent run
  over A2A through the kagent oauth2-proxy Service with `Authorization: Bearer <the caller's
  token>` and the trace context, and return a run ID within 10 seconds.
- **REQ-07** WHEN `research_status` or `research_result` is called THE SERVER SHALL answer
  from the A2A task **only if it belongs to the caller** (the run was started with the
  caller's token); otherwise it SHALL answer "not found".
- **REQ-08** `research_result` SHALL return the report text with its numbered citations and
  source URLs, cut to the connector's output limit with a note and the kagent UI link when
  longer.
- **REQ-09** THE SERVER SHALL allow one run in progress per user and cancel a run after 10
  minutes (as H-006 REQ-12, REQ-14).
- **REQ-10** WHEN a tool call waits on a run THE SERVER SHALL return before claude.ai's tool
  timeout, as measured in EVAL-06 (holds open at most that minus a margin, then answers
  "still running").
- **REQ-11** IF kagent or research-agent is unreachable THEN THE SERVER SHALL answer with a
  fixed message and a reference ID, never a stack trace (as H-006 REQ-16).

### Boundaries

- **REQ-12** Tokens and refresh tokens SHALL never appear in logs, traces or tool output.
  The server stores no tokens: claude.ai holds them.
- **REQ-13** THE SERVER's egress SHALL be limited to Cognito's endpoints and the kagent
  oauth2-proxy Service; its ingress to the connector ALB only.
- **REQ-14** Only `research.<domain>` (served by research-mcp alone) SHALL be reachable
  from Anthropic's ranges. The hub ALB (kagent, Phoenix, OpenBao) SHALL stay behind your
  /32s, and the connector ALB SHALL accept routes from the `agents` namespace only.
- **REQ-15** WHEN the server is stopped THE kagent UI and Slack SHALL keep working, showing
  the conversations and reports started from claude.ai.

## Tools

Shared fields for all tools: side effects through research-agent only; trifecta legs as
research-agent's own (untrusted content ☑, outbound ☐ for the tools themselves); boundary
rule allow; human in the loop n/a.

### `research_start`

| Field | Value |
|---|---|
| Purpose | Ask research-agent a research question; it searches, reads sources and writes a cited report (about 1–3 minutes) |
| Use when / not when | A question needing several sources and citations. Not for quick facts (use Claude's own search) |
| Input schema | `{question: string (10–2000 chars)}`, `additionalProperties: false` |
| Output | Run ID, "started", and the advice to call `research_result` |
| Side effects | starts a model run (cost: about $0.30 median) |
| Risk tier | medium (spends money) |
| Idempotent | no: a second call starts a second run (blocked while one is running, REQ-09) |
| Errors | "A run is already in progress: <run ID>"; "The AI Hub is down: start it with the AI Hub connector" |

### `research_status` and `research_result`

| Field | Value |
|---|---|
| Purpose | Progress of a run; its report when finished |
| Input schema | `{run_id: string}` |
| Output | Status (`working`, `done`, `failed`, `cancelled`), elapsed time; for `research_result` the report |
| Side effects | none · Risk tier low · Idempotent yes |
| Errors | "Run not found" (also for another user's run, REQ-07) |

### `list_my_reports`, `get_report`

Read-only, the caller's own reports from the reports bucket through the same path the UI
uses. Risk tier low.

## Guardrails

- **GUARD-01** Same principal as the UI and Slack: identity only from a Cognito-signed
  token, checked by the server (REQ-04) and again by oauth2-proxy. The controller's network
  policy is unchanged.
- **GUARD-02** claude.ai is a new untrusted-input source and a new outbound channel for
  report text: added to research-agent's trifecta declaration (doc only, as H-006 task 5).
- **GUARD-03** The opening is a separate ALB (REQ-14) with one hostname; a check fails if
  a hub host answers from outside the allowlist or another route attaches (EVAL-05).
- **GUARD-04** No credentials in the server: no client secret (public client), no stored
  tokens (REQ-12).

## Memory and context

- Server memory: run ID → A2A task and owner `sub`. Lost on restart; a lost run's report is
  still in the kagent UI and `list_my_reports`. Accepted.
- One A2A context per run (no follow-ups in the same context). [Later: follow-ups if
  wanted.]
- Conversations and reports stay in kagent and the reports bucket.

## Budgets

| | Limit | Kind |
|---|---|---|
| Runs in progress per user | 1 | hard (REQ-09) |
| Run wall clock | 10 min | hard (REQ-09) |
| Runs per user per day | 20 | hard: placeholder until cost caps |
| Cost per run | research-agent's own `max_usd` | hard, unchanged |
| Time to `research_start` answer | 10 s | hard (REQ-06) |
| Median time to report | under 3 min | soft: as on the UI and Slack paths |

## Human in the loop

n/a: research-agent has no high-risk tools. claude.ai asks you before calling a tool unless
you allow it.

## Observability

- A span per MCP request (`mcp.request`), with child spans for the token check, the A2A
  call and each poll. Attributes: hashed `sub`, tool name, run ID, A2A context and task
  IDs, outcome, duration, `via=claude`. The A2A call carries the trace context so the
  research-agent trace links under it in Phoenix.
- Structured log lines for refusals (`mcp refused` with the reason: no token, bad
  signature, wrong audience, expired, not assigned) and OAuth steps (status codes only),
  with the caller's source IP, to confirm Anthropic's ranges in practice.
- Connector ALB access logs during the evals (what claude.ai sends, retries,
  timing).
- Cost per run is in research-agent's traces already; `via=claude` lets H-005's views split
  it out.
- Never recorded: tokens, question or report text beyond what research-agent records.

## Failure modes

| FM | Failure | Control | Proving test or eval |
|---|---|---|---|
| FM-01 | One user reads another's run or report | owner check on run ID (REQ-07); reports by the caller's token | unit: two users; e2e: EVAL-04 |
| FM-02 | A forged or self-signed token reaches the controller | server checks signature (REQ-04); oauth2-proxy checks again; server never makes tokens (REQ-03) | unit: forged tokens; e2e: EVAL-04 |
| FM-03 | The ALB opening exposes the UI or other hosts to Anthropic's range | separate ALB, one hostname (REQ-14) | EVAL-05 |
| FM-04 | claude.ai times out waiting and retries, starting a second run | short `research_start` (REQ-06), one run per user (REQ-09), hold-open below the timeout (REQ-10) | unit: duplicate call; EVAL-06 |
| FM-05 | Removed user keeps access | 7-day refresh (REQ-05); oauth2-proxy and Cognito refuse after that | unit: expired token → 401 |
| FM-06 | Token or secret in logs | redaction, test on captured output (REQ-12) | unit: log capture scan |
| FM-07 | Hub down: a hang or a confusing error | claude.ai gets a connection error; the AI Hub connector's `hub_status` explains | EVAL-07 |
| FM-08 | Report too long for the chat | cut with UI link (REQ-08) | unit: 60,000-char report |

## Acceptance

Unit tests with a fake Cognito (JWKS), a fake A2A server and a scripted claude.ai OAuth and
MCP flow cover REQ-01 to REQ-13. End to end from claude.ai, with the hub up:

- **EVAL-01** Discovery and sign-in: add the connector by the `operations.md` steps,
  connect as `agentgrid`; the log shows the token exchange (200) and a tool list. (REQ-01
  to REQ-03)
- **EVAL-02** Golden-set questions asked in claude.ai: research-agent's own bar (k=1 at
  least 8 of 10), median under 3 minutes, cost under $0.50, graded from the hub's traces
  and reports as H-006 EVAL-01. (REQ-06 to REQ-10)
- **EVAL-03** A report asked for in claude.ai appears for the same user in the kagent UI.
  (REQ-06, REQ-15)
- **EVAL-04** Unsigned, expired and other-client tokens are refused (401); a second user's
  run ID returns "not found". (REQ-04, REQ-07)
- **EVAL-05** From an address outside your /32s, the kagent, Phoenix and OpenBao hosts
  don't answer; the connector ALB serves only `research.<domain>` (another Host header
  gets 404) and lists one route. (REQ-14)
- **EVAL-06** Timeout probe: a test tool that holds the call open 30, 60, 120, 240 s; record
  where claude.ai gives up and whether it retries; set REQ-10's hold-open from it. Run
  before EVAL-02.
- **EVAL-07** Hub down: a tool call fails quickly with a clear error, and Claude can tell
  you to start the hub with the AI Hub connector. (FM-07)
- **Safety invariants (0 violations):**
  - no A2A call without a Cognito-issued token for the calling user
  - no token, secret or stack trace in tool output, logs or traces
  - no host other than `research.<domain>` reachable from outside the allowlist
  - no second concurrent run per user

Model spend for the evals: about $3–4 (EVAL-02, as H-006), plus the hub while it's up.

## Tasks

1. Q1 to Q4 answered and HD-007 accepted, 2026-11-25.
2. Confirm on the cluster that oauth2-proxy accepts an ID token of a new client's audience
   as a bearer token (as H-006 task 2; the `extra-jwt-issuers` entry) and that kagent sees
   the same principal as in the UI. Done 2026-11-25: passed (Results).
3. openbao-platform: the `research-mcp-claude` Cognito client; the oauth2-proxy
   `extra-jwt-issuers` entry; the connector ALB (`connector-gateway`, Anthropic's
   ranges plus your /32s); ECR repo; remove the check's localhost callback; decision
   D-35. Done 2026-11-25 (openbao-platform `447cda3`, applied; Results).
4. The server (repo `research-mcp`): MCP over streamable HTTP, the OAuth pass-through and metadata
   (ported from hub-control), the A2A client (from `slack-bridge`), OTel, unit tests.
   Done 2026-11-25: local repo `research-mcp` (Results); not on GitHub yet.
5. Image (trixie, non-root, Trivy clean of fixable findings), release script, manifests in
   `deploy/agents/research-mcp.yaml` with a network policy (REQ-13).
6. research-agent: add claude.ai to the trifecta declaration (doc only).
7. EVAL-06 first, then set REQ-10; then EVAL-01 to EVAL-05 and EVAL-07. EVAL-06 done
   2026-11-25: `HOLD_S` = 45 s (Results).
8. `docs/operations.md` (connector setup for **Research**, as for **AI Hub**),
   `stack.sh` checks, architecture and IcePanel diagrams; tick the roadmap box.

## Results

- 2026-11-25, task 2 (oauth2-proxy check): **passed, 7 of 7**
  (`scripts/check-research-mcp-token.py`, openbao-platform `385bfb7` applied: Cognito client
  `research-mcp-claude`, a second `extra-jwt-issuers` audience). Signed in as `agentgrid`
  through the new client; on research-agent's agent card through the kagent host: no token
  403; the client's ID token 200; broken signature 403; another audience 403; the client's
  **access** token 403 (confirms REQ-03: claude.ai must get the ID token); a refreshed ID
  token 200. The token's `iss` and `sub` (`a84183f0-…`) are the same as the user's in the
  UI and Slack, which is how kagent identifies the principal (HD-006), so the same user is
  seen through every way in. Regression: a Slack DM to research-agent afterwards was
  answered (the bridge's audience still accepted alongside the new one).
- 2026-11-25, task 3 applied: Gateway `connector` Accepted and Programmed, 0 routes; ALB
  `openbao-nonprod-connector` active, its security group admits 443 from exactly
  `160.79.104.0/21`, `153.61.208.0/20` and the two allowlisted /32s; the hub ALB's group
  still admits only the /32s. The connector ALB has **no listener** until a route attaches
  (the load balancer controller creates it with the first route), so nothing answers from
  Anthropic's ranges before task 5. ECR `research-mcp` (immutable tags);
  `research-mcp-claude` now has only claude.ai's callback.
- 2026-11-25, task 4: local repo `research-mcp` (Python, Starlette, `a2a-sdk` 1.3, PyJWT),
  28 offline tests with a fake Cognito signing real RS256 tokens, a fake A2A endpoint and a
  fake reports service. Guards checked by mutation (each fails a test when removed):
  `token_use`, audience, run owner (REQ-07), one run per user (REQ-09), handing out the ID
  token (REQ-03), the claude.ai-only redirect (REQ-02), the 404 mapping of `get_report`,
  and no question in the logs (REQ-12). `HOLD_S` defaults to 45 s until EVAL-06; the
  `debug_hold` probe tool appears only with `PROBE_TOOL=1`.
- 2026-11-25, task 5 deployed: image `8cb4024` (Trivy: the first build had 4 fixable
  Starlette findings, 2 HIGH; Starlette 1.10 rebuilt clean, 0 fixable in Debian and
  Python), openbao-platform `8aa1a05` (layer 50: `kv/projects/research-mcp/cognito`).
  Argo CD synced in about 7 minutes: ExternalSecret synced, pod ready, the connector ALB
  gained its HTTPS listener and one healthy target, ExternalDNS wrote
  `research.<domain>`. From outside: `/mcp` without a token 401 with the
  `resource_metadata` challenge; both discovery documents served; `/oauth/authorize` with
  an unknown client 400; another Host header on the connector ALB 404.
- 2026-11-25, EVAL-06 (timeout probe, `debug_hold` from claude.ai): 30 s returned; 60, 120
  and 240 s failed in claude.ai as "Bad Gateway". The server completed the holds it logged
  (30, 60, 120 s); the connector ALB counted three 504s: its idle timeout (60 s default)
  cuts the call before claude.ai's own limit, which stays unmeasured. **`HOLD_S` = 45 s**
  (REQ-10), the ALB unchanged; `research_result` says "still running" and Claude calls
  again. Probe tool removed. Same log: calls came from `160.79.106.x` (inside Anthropic's
  `160.79.104.0/21`), and the sign-in's token exchange returned 200 (EVAL-01, sign-in part).
