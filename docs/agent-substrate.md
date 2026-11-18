# Agent Substrate with `kubectl ate`

How the hub's agents run on Agent Substrate 1.0, and the `kubectl ate` commands to inspect
and manage them. Commands checked against the installed plugin and the cluster on
2026-11-18. Install notes: `~/openbao/infra/45-agent-substrate/README.md`.

## The model in five terms

| Term | What it is on this hub |
|---|---|
| **Atespace** | A tenant boundary for actors. There is one: `kagent`. |
| **Actor** | One running (or suspended) agent instance. kagent creates **one actor per chat session**, named `session-<id>`. |
| **Actor template** | What an actor starts from, one per agent revision (`research-agent-<hash>`, `secrets-agent-<hash>`). Each has a **golden snapshot tag**: new sessions resume from it instead of booting. A new revision (new image, prompt or tools) makes a new template. |
| **Worker** | A pod that hosts actors in a gVisor sandbox. Pool `kagent-default` in namespace `kagent`. |
| **Snapshot / tag** | Suspending an actor snapshots it (to the worker's node, then S3 `openbao-nonprod-agent-snapshots-…`); resuming restores it. Tags name snapshots (the golden ones among them). |

kagent drives all of this: idle sessions are suspended, a new message resumes them. You
rarely need to act by hand; these commands are for seeing what's going on and for
recovering a stuck session.

## Before you start

```bash
export AWS_PROFILE=agentgrid          # kubeconfig for openbao-nonprod
kubectl ate get atespace              # quick check: lists `kagent`
```

Every command prints `Warning: no --token-file given; acting as the shared identity
system:serviceaccount:ate-system:ate-client`. As a cluster admin that's expected; pass
`--token-file` only to act as a specific identity.

Global flags: `-o table|json|yaml`, `-v` / `-vv` (more detail), `--trace`,
`--endpoint host:port` (skip the automatic port-forward to the ate API).

## Look around (read-only, safe)

```bash
kubectl ate get atespace                              # atespaces
kubectl ate get actor -A                              # all actors: template, state, worker pod, age
kubectl ate get actor -a kagent <actor> -o yaml       # one actor in full
kubectl ate get actor-template -A                     # templates and their golden snapshot tags
kubectl ate get actor-template -a kagent <template> -o yaml
kubectl ate get worker                                # workers: pool, state, actor/CPU/memory capacity
kubectl ate get worker --sandbox-class gvisor         # filters: -n <namespace>, -l <pool labels>, -a <atespace>
kubectl ate top worker                                # CPU/memory per worker pod
kubectl ate get egress-policy -a kagent <actor>       # what an actor may reach outside the cluster
kubectl ate get access-policy -a kagent               # who may use the atespace (omit -a: global policy)
kubectl ate get tag -A                                # snapshot tags
```

Actor states you'll see: `ACTOR_STATE_RUNNING` (on a worker, `WORKER POD` filled in) and
`ACTOR_STATE_SUSPENDED` (snapshot only, no worker).

**Which actor is my chat?** `kubectl ate get actor -A`: the newest `AGE` is the latest
session; the `TEMPLATE` column says which agent (research-agent or secrets-agent) and which
revision.

## Debug a session

```bash
kubectl ate logs actor -a kagent <actor> -f                    # follow everything
kubectl ate logs actor -a kagent <actor> --source lifecycle    # start / suspend / resume events only
kubectl ate logs actor -a kagent <actor> --source containers   # the agent's own output only
kubectl ate logs actor -a kagent <actor> -c <container>        # one container
kubectl ate logs actor -a kagent <actor> -c _sandbox           # gVisor (runsc) diagnostics
kubectl ate proxy actor -a kagent <actor> 8080:8080            # local port -> actor port (running actors)
```

## Lifecycle (changes state: use deliberately)

```bash
kubectl ate suspend actor -a kagent <actor>                # snapshot, free the worker (default --mode async)
kubectl ate suspend actor -a kagent <actor> --mode sync    # return only once the snapshot is in S3
kubectl ate resume  actor -a kagent <actor>                # bring it back from its snapshot
kubectl ate revert  actor -a kagent <actor>                # throw away changes since its latest snapshot
kubectl ate update  actor -a kagent <actor> --template <template>   # repoint to another revision
kubectl ate update  actor -a kagent <actor> --worker-selector key=value   # pin to worker pools
kubectl ate delete  actor -a kagent <actor>                # remove the actor (the chat's state goes with it)
```

When to use them:
- **A session is stuck** (spinning, no reply): `logs --source lifecycle`, then `revert` or
  `delete` the actor and start a new chat.
- **Free a worker** without waiting for kagent's idle timeout: `suspend`.
- **Clean up** after evals: suspended actors use no worker, but their snapshots stay in S3
  until deleted. `stack.sh down` clears everything anyway.

## Create, update and policies: leave to kagent

The plugin can also `create` / `update` / `delete` actor templates, egress policies,
access policies, atespaces and tags (`kubectl ate create egress-policy -f …`, etc.). On
this hub, kagent and Argo CD own those objects, built from the `Agent`, `Harness`,
`AgentTemplate` and `EgressPolicy` resources in this repo (`deploy/kagent/`). A hand edit
is overwritten or drifts from Git: change the manifests here instead.

`kubectl ate update tag` publishes or unpublishes a tag; `kubectl ate create tag` tags the
snapshot a suspended actor holds. Not needed in normal use.

## Admin: signing keys

```bash
kubectl ate admin list-jwt-keys        # keys in the JWT authority pool (actor identity)
kubectl ate admin add-jwt-key          # add an inactive key
kubectl ate admin activate-jwt-key     # make it the signing key
kubectl ate admin remove-jwt-key       # remove an inactive key
kubectl ate admin make-jwt-pool        # new JWT authority pool secret
kubectl ate admin make-ca-pool         # new CA pool secret for a signing controller
```

Only for planned key rotation. Run `kubectl ate admin <command> --help` first.

## Related plain kubectl

```bash
kubectl -n kagent get agents,harnesses,agenttemplates,egresspolicies   # kagent's view
kubectl -n kagent get agent secrets-agent -o yaml | grep -A3 Ready      # e.g. golden snapshot pending
kubectl -n kagent get pods -l ate.dev/worker-pool=kagent-default        # the worker pods
kubectl -n ate-system get pods                                          # Substrate's controllers
```

`Ready=False … ActorTemplatePending: waiting for the ActorTemplate golden snapshot` on an
Agent is normal for a few minutes after a change: Substrate is building the new
revision's golden snapshot.
