# Mission

> **Pitch:** Edward's AI Hub is a portal where signed-in users talk to a growing set of AI
> agents, each running in its own sandbox on Kubernetes, with every agent's guardrails and
> costs enforced in code.

## Summary

Users sign in with their IAM Identity Center account and open kagent's UI. They pick an
agent, ask it something, and get the answer in the chat, plus a file where the agent
produces one. Each conversation runs in its own gVisor sandbox on Agent Substrate and is
snapshotted when idle. The platform controls what an agent can reach; each agent's own
harness controls what it does with it.

## Users

- **Operator:** me. I deploy agents through ArgoCD and read traces and costs.
- **Portal users:** people I add in IAM Identity Center. They use agents through kagent's UI.
- **Agent authors:** me for now. Each agent lives in its own repo with its own specs.
- **Who else is affected:** the sites and APIs agents call. Each agent must be a polite
  client.

## The problem

Each agent built so far runs on a laptop from a terminal. Sharing one means a hosted
endpoint with sign-in, isolation between users, durable output, cost control and a way to
add the next agent without rebuilding the platform.

## What the hub does

- Signs users in through IAM Identity Center and keeps each conversation private to its owner.
- Runs each conversation in its own sandbox, suspending it when idle.
- Lets an operator add an agent with manifests in Git, through ArgoCD.
- Collects traces, token use and cost per agent and per user.

## What the hub will never do

Each of these is enforced by configuration or code, and has a check that fails if removed.

- **Never expose an agent or tool server outside the cluster except through the
  authenticated portal.** MCP servers have no Ingress.
- **Never put credentials in an agent's sandbox.** Keys are added by agentgateway, or AWS
  access comes from a workload identity.
- **Never let one agent complete another's lethal trifecta.** An agent that reads untrusted
  content and can send data out may not call, or be called with results from, an agent that
  reads private data.
- **Never show one user's conversations, reports or traces to another user** unless the
  owner shares them.
- **Never change the cluster by hand.** Everything goes through Git and ArgoCD.
- **Never upgrade kagent or Agent Substrate unpinned.** Versions move together, on purpose.

## Success looks like

Placeholders until the first deployment gives baselines:

- A signed-in user gets a research report in the portal in under 3 minutes (median), the same
  target research-agent meets on a laptop.
- Adding a second agent needs no change to the platform, only that agent's manifests.
- Zero cross-user data leaks and zero public endpoints in the acceptance checks.
