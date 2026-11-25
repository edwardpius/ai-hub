# Edward's AI Hub

A portal that offers AI agents to signed-in users, running on kagent / Agent Substrate in EKS
and deployed with ArgoCD. research-agent is the first agent.

This folder holds the hub's product docs. It moves into the cluster repo when that repo
exists. The agents keep their own repos and specs; this folder covers the platform they run
on and the rules every agent must meet to join.

| Start here | |
|---|---|
| [docs/operations.md](docs/operations.md) | **Start, use and stop the hub; what it costs** |
| [docs/slack-integration.md](docs/slack-integration.md) | Asking research-agent from Slack: how it works, as built, setup |
| [docs/assessment.md](docs/assessment.md) | Why research-agent is deployed directly, not wrapped, and how |
| [product/mission.md](product/mission.md) | Why the hub exists and what it will never do |
| [product/roadmap.md](product/roadmap.md) | Phases and progress (the only place status lives) |
| [product/tech-stack.md](product/tech-stack.md) | Platform principles, stack and open decisions |
| [product/decisions.md](product/decisions.md) | Why things are the way they are |

The workflow is the same as research-agent's
(`WORKFLOW.md` in the private research-agent repo): status only in the roadmap,
EARS requirements with stable IDs, `[NEEDS CLARIFICATION]` blocks implementation, and a
box is ticked only when its acceptance checks pass. Hub specs are numbered `H-NNN` and are
written in the cluster repo.
