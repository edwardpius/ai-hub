# H-006 – Ask research-agent from Slack

**Roadmap:** Phase 5 / Slack bridge · **Status:** see `product/roadmap.md` (never here)
**Decision:** HD-006 · **Plan and findings:** `docs/slack-integration.md`

Hub specs belong in the cluster repo (README); this one sits here until that repo has a
`specs/` folder.

## Intent

A signed-in hub user asks research-agent a question in Slack, in a channel or a DM, and gets
the report back in the same thread, as the same user they are in the kagent UI. Slack is a
second way in, never the only one: the UI keeps working with Slack down, and both show the
same conversations and reports. This serves the mission of offering the hub's agents to
signed-in users where they already work.

**Out of scope:**
- Other agents (one agent, `kagent/research-agent`; routing is a later spec).
- research-agent posting to Slack itself (no Slack tool or MCP server for the agent).
- Slack's public Events API, slash commands, Slack Marketplace distribution.
- Opening the ALB allowlist to more addresses.
- Changes to kagent or to research-agent's code.

## Requirements

### Linking accounts

- **REQ-01** WHEN a Slack user without a link mentions the bot or messages it THE BRIDGE
  SHALL reply with a message only that user can see, holding a sign-in link, and SHALL NOT
  call research-agent.
- **REQ-02** WHEN the user completes sign-in THE BRIDGE SHALL exchange the code with PKCE and
  a `state` value bound to that Slack user and workspace, and store the refresh token in
  OpenBao under that Slack user ID.
- **REQ-03** IF the sign-in callback's `state` is missing, expired (over 10 minutes), reused,
  or bound to a different Slack user THEN THE BRIDGE SHALL refuse it and store nothing.
- **REQ-04** IF the user isn't assigned to the app in Identity Center THEN sign-in SHALL fail
  at Cognito and THE BRIDGE SHALL store nothing.
- **REQ-05** WHEN a linked user sends `disconnect` THE BRIDGE SHALL revoke the refresh token at
  Cognito, delete it from OpenBao, and confirm privately.
- **REQ-06** IF a refresh fails (expired, revoked, user removed) THEN THE BRIDGE SHALL delete
  the stored token and treat the user as unlinked (REQ-01).
- **REQ-07** The refresh-token lifetime of the bridge's Cognito client SHALL be 7 days, which
  bounds how long a user removed from Identity Center keeps Slack access (resolved
  2026-11-19).

### Asking

- **REQ-08** WHEN a linked user mentions the bot in an allowed channel, or sends it a DM, THE
  BRIDGE SHALL acknowledge the event within 3 seconds and post a "researching…" reply in the
  message's thread.
- **REQ-09** THE BRIDGE SHALL call research-agent at `POST /agents/kagent/research-agent`
  (A2A JSON-RPC, streaming) through the kagent oauth2-proxy Service
  (`kagent-oauth2-proxy.kagent:4180`, then kagent-signout to the controller; openbao-platform
  D-28), with `Authorization: Bearer <that user's Cognito ID token>`, refreshed at the start
  of each run (the ID token lives 15 minutes, longer than the 10-minute run cap).
- **REQ-10** THE BRIDGE SHALL map one Slack thread to one A2A context: the first message
  starts a new context, and later messages in that thread continue it.
- **REQ-11** WHILE a run is in progress THE BRIDGE SHALL update the "researching…" reply with
  research-agent's progress at most once every 5 seconds.
- **REQ-12** IF the user already has a run in progress THEN THE BRIDGE SHALL reply that a
  run is in progress and SHALL NOT start another.
- **REQ-13** THE BRIDGE SHALL ignore messages from bots (its own included), edits, and
  messages in channels not on its allowlist.
- **REQ-14** IF a run takes longer than 10 minutes THEN THE BRIDGE SHALL cancel the A2A task
  and say so in the thread.

### Answering

- **REQ-15** WHEN the run completes THE BRIDGE SHALL post in the thread a summary (converted
  to Slack mrkdwn, split to fit Slack's block and message limits), the full report as a `.md`
  file (`files.uploadV2`), and the report's `/reports/` download link.
- **REQ-16** IF the run fails THEN THE BRIDGE SHALL post a short error in the thread with a
  reference ID, and SHALL NOT post exception text, stack traces, URLs of internal services
  or tokens. Details go to the bridge's log and trace under that ID.

### Identity, secrets and network

- **REQ-17** THE BRIDGE SHALL NOT create, sign or alter a JWT; it only forwards tokens
  Cognito issued.
- **REQ-18** Slack tokens, the Cognito client secret and users' refresh tokens SHALL live
  only in OpenBao and the pod's memory or secret mounts, never in the image, logs, traces or
  Slack.
- **REQ-19** THE BRIDGE's egress SHALL be limited to Slack (`slack.com`,
  `*.slack.com` for Socket Mode), Cognito's endpoints, OpenBao, and the kagent oauth2-proxy
  Service; its ingress to the sign-in callback through the kagent host.
- **REQ-20** WHEN the bridge is stopped THE kagent UI SHALL keep working for every user,
  showing the conversations and reports started from Slack.

## Tools

n/a: the bridge is a client of research-agent, not an agent; it adds no tool to any agent.

## Guardrails

- **GUARD-01** Same principal as the UI: identity comes only from a Cognito-signed token,
  checked by oauth2-proxy (REQ-09, REQ-17). The controller's network policy is unchanged.
- **GUARD-02** Slack messages are untrusted input to research-agent, and the bridge posts its
  output to Slack. research-agent's trifecta declaration gains Slack as an untrusted-input
  source and an outbound channel. research-agent's own guards (fetch allowlist, citation
  check) are unchanged.
- **GUARD-03** Refresh tokens are user credentials: they live in their own OpenBao mount,
  `slack-links/<team ID>/<user ID>` (one version), which only the bridge's policy can read.
  Admins can list and delete links, not read them; no `kv/` rule reaches the mount.
- **GUARD-04** Channel allowlist (REQ-13): the bot answers only where it was explicitly
  allowed, plus DMs.

## Memory and context

- OpenBao `slack-links/<team ID>/<user ID>`: refresh token, linked Cognito `sub`, link
  time. Destroyed (all versions) on `disconnect` or failed refresh.
- Bridge memory: Slack thread → A2A context ID, the per-user running flag, pending `state`
  values. Lost on restart; a follow-up in an old thread then starts a new context, and the
  bridge says so. Accepted for now (resolved 2026-11-19); revisit storing the map in OpenBao
  if lost follow-ups become a problem.
- Conversations and reports stay in kagent and the reports bucket, as for UI use.

## Budgets

| | Limit | Kind |
|---|---|---|
| Runs in progress per user | 1 | hard (REQ-12) |
| Run wall clock | 10 min | hard (REQ-14) |
| Runs per user per day | 20 | hard: placeholder until cost caps (roadmap Phase 4) |
| Cost per run | research-agent's own `max_usd` | hard, unchanged |
| Time to first reply | 3 s | hard (Slack's limit) |
| Median time to report | under 3 min | soft: as on the UI path |

## Human in the loop

n/a: research-agent has no high-risk tools. Linking is the user's own sign-in.

## Observability

- A span per Slack event (`slack.event`), with child spans for token refresh, the A2A call
  and each Slack post. Attributes: hashed Slack user ID, channel ID, thread ts, A2A context
  and task IDs, outcome. The A2A call carries the trace context so the research-agent trace
  links under it in Phoenix.
- Never recorded: tokens, Slack message text beyond what research-agent already records
  (HD-004 content capture applies to the agent, not the bridge).

## Failure modes

| FM | Failure | Control | Proving test or eval |
|---|---|---|---|
| FM-01 | One user's request runs as another user | `state` bound to Slack user (REQ-03); token looked up by event's user ID | unit: crossed `state`; e2e: two users, reports land in each own prefix |
| FM-02 | A forged or self-signed token reaches the controller | oauth2-proxy checks the signature; bridge never makes tokens (REQ-17) | e2e: unsigned token through the proxy → 401 |
| FM-03 | Removed user keeps access | short refresh lifetime (REQ-07), failed refresh unlinks (REQ-06) | unit: refresh 400 → unlinked |
| FM-04 | Slack retries a slow event and two runs start | ack within 3 s (REQ-08), dedupe on event ID, one run per user (REQ-12) | unit: duplicate event delivery |
| FM-05 | Long report rejected by Slack | split to limits, full text as a file (REQ-15) | unit: 60,000-char report |
| FM-06 | Internal details leak into a channel | fixed error text with reference ID (REQ-16) | unit: exception with secret-looking text |
| FM-07 | Bot answers itself or another bot in a loop | ignore bot messages (REQ-13) | unit: bot_message event |
| FM-08 | Slack down | UI unaffected (REQ-20) | e2e: bridge scaled to 0, UI run works |
| FM-09 | Token or secret in logs | structured logging with redaction, test on captured output | unit: log capture scan |

## Acceptance

Unit tests with a fake Slack, a fake Cognito and a fake A2A server cover REQ-01 to REQ-19.
End to end in a test Slack workspace, with the hub up:

- **EVAL-01** Golden-set questions asked in Slack: research-agent's own bar (k=1 at least 8 of
  10), median under 3 minutes, cost under $0.50. (REQ-08 to REQ-11, REQ-15)
- **EVAL-02** A report asked for in Slack appears for the same user in the kagent UI and its
  download works. (REQ-09, REQ-20)
- **EVAL-03** A follow-up in the thread continues the same context. (REQ-10)
- **EVAL-04** A user not assigned in Identity Center can't link and gets no answer. (REQ-01,
  REQ-04)
- **EVAL-05** `disconnect`, then a question: asked to link again. (REQ-05)
- **EVAL-06** An unsigned token through oauth2-proxy is refused. (FM-02)
- **EVAL-07** Bridge scaled to 0: a UI run works and shows the Slack-started conversations.
  (REQ-20)
- **Safety invariants (0 violations):**
  - no A2A call without a Cognito-issued token for the asking Slack user
  - no token, secret or stack trace in Slack, logs or traces
  - no reply in a channel not on the allowlist
  - no second concurrent run per user

## Tasks

1. openbao-platform: the bridge's Cognito app client; oauth2-proxy bearer-token settings;
   callback route on the kagent host; OpenBao path and policy; ECR repo. Done as local
   commit `b5f074f` (D-28), not applied; pushed only when you say so.
2. Confirm on the cluster that oauth2-proxy passes `Authorization` to the controller
   unchanged for a bearer request (blocks the design of REQ-09; fallback in HD-006).
3. `slack-bridge` repo: Bolt app, A2A client, OAuth callback, OpenBao client, unit tests.
   Done as local repo `slack-bridge`, commit `e07c0b3` (35 offline tests); not pushed.
4. Image (trixie, non-root, pip removed, Trivy clean of fixable findings),
   `scripts/release-slack-bridge.sh`, manifests in `deploy/agents/`, Argo CD app.
5. research-agent: add Slack to the trifecta declaration (doc only).
6. Slack app in a test workspace (operator); tokens into OpenBao.
7. `stack.sh` and `docs/operations.md`; end-to-end evals; tick the roadmap box.
