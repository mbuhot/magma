# Magma: Durable Workflows for Ash

Magma makes a Reactor survive process death. A workflow runs inside an Oban job, each
step checkpoints its output, and every later attempt replays the recorded outputs and
carries on from the edge of what finished.

It composes tools that already exist. Reactor supplies the DAG, the concurrency, the
compensation and the undo. Oban supplies the durable execution slot, the retry backoff
and the scheduling. Ash supplies the store. Magma is the decoration that ties the three
together.

## Table of contents

- [Shape](#shape)
- [Authoring](#authoring)
- [The three decorations](#the-three-decorations)
- [Concurrency and ordering](#concurrency-and-ordering)
- [The replay contract](#the-replay-contract)
- [Actor and tenant](#actor-and-tenant)
- [Waiting](#waiting)
- [Outcomes](#outcomes)
- [Unwinding](#unwinding)
- [Resources](#resources)
- [Modules](#modules)
- [Testing](#testing)
- [Milestones](#milestones)
- [Open questions](#open-questions)

## Shape

```
Magma.start(MyWorkflow, inputs, opts)
  ├─ insert magma_workflows row  (id, module, inputs, status: :pending)
  └─ Oban.insert(Magma.Worker, %{workflow_id: id})     ── one transaction
```

`Magma.Worker.perform/1`, on every attempt:

| Step | |
|---|---|
| 1 | Load the workflow row and all its checkpoints |
| 2 | `MyWorkflow.reactor()` — a fresh, unplanned `%Reactor{}` |
| 3 | Walk `reactor.steps` and decorate each one |
| 4 | `Reactor.run/4` |
| 5 | Map the outcome onto a workflow status and an Oban return value |

Step outputs are the only thing that persists between attempts. The DAG is re-planned
from the DSL every time, which collapses the halt path and the crash path into one path.

## Authoring

A Reactor extension, composing with `Ash.Reactor`:

```elixir
defmodule MyApp.Checkout do
  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  magma do
    queue :payments
    max_attempts 20
  end

  input :order_id

  read_one :order, MyApp.Sales.Order, :by_id do
    inputs %{id: input(:order_id)}
    fail_on_not_found? true
  end

  step :quote, MyApp.Payments.Quote do
    argument :amount, result(:order, [:total])
  end

  await :confirmation, signal: "confirm", timeout: :timer.hours(48) do
    argument :quote, result(:quote)
  end

  step :charge_card, MyApp.Payments.Charge do
    argument :quote, result(:quote)
    argument :approval, result(:confirmation)
  end

  update :mark_paid, MyApp.Sales.Order, :mark_paid do
    initial result(:order)
    inputs %{charge_id: result(:charge_card, [:id])}
  end

  return :mark_paid
end
```

State flows through Reactor's own argument templates. `input/1` reads the workflow's
inputs; `result/1` and `result/2` read a named step's output, optionally down a path.
Magma adds no state channel of its own, and that omission is what makes replay work:

> **Arguments hold no checkpoint. Outputs do.**

On every attempt each step's arguments are rebuilt from the recorded outputs of the steps
upstream and the inputs on the workflow row, so they are identical by construction. A
step whose output is already recorded is skipped whatever its arguments say, so argument
transforms matter only for steps still to run.

`await` is an ordinary node in that graph — it takes arguments, its result is
`result(:confirmation)`, and `wait_for` orders it against steps it reads nothing from.

One `Magma.Worker` carries the reactor module in its args, so no worker module is
generated per workflow and `Reactor.Info` supplies the rest.

## The three decorations

| Mechanism | Job |
|---|---|
| **Guard**, prepended to `step.guards` | A recorded output produces `{:halt, {:ok, value}}`. The step's own `where` guards stay unevaluated for work already done. |
| **Impl wrapper** — `impl: {Magma.Checkpointed, inner: impl, name: name}` | Writes the checkpoint transactionally after a successful run, decorates dynamically returned steps, and intercepts `undo`/`compensate`. |
| **Middleware** | Records guard-skip decisions, workflow lifecycle, telemetry. |

The impl wrapper owns the checkpoint write because a failed write has to fail the step.
Middleware `event/3` returns `:ok` and can only observe, so it carries the advisory
records.

### Composite steps re-plan

`map`, `switch`, `group`, `around`, `compose` and `recurse` return `{:ok, value, steps}`.
Those generated steps hold iterators and closures, which puts them outside what
`term_to_binary` can carry.

**A step that returns new steps is a planning step and holds no checkpoint.** It re-runs
on replay, re-plans identically, and its generated children carry the checkpoints. The
split between a body that re-executes and steps that do not lands on Reactor's own seam.

## Concurrency and ordering

Reactor's semantics survive intact. Ready steps run concurrently in Tasks, each writes its
own checkpoint as it completes, and the rows land in whatever order the work finishes.

Replay reads them as a map keyed by step name. Insertion order stays out of it: the DAG
is re-derived from the DSL by Reactor's planner, and the topology is what decides which
steps are runnable. A checkpoint answers one question — has this step finished, and with
what value.

That keeps the contract narrow. Against an engine that identifies a step by a counter
allocated in execution order:

| | Counter-identified | Magma |
|---|---|---|
| A step's identity | its position in the call sequence | its declared name |
| Adding a step | shifts every position after it, so old runs need a patch guard | it runs; everything else replays |
| Reordering steps | changes the recorded sequence | the DAG is the order |
| Branching | the same branch has to be taken on replay | `switch` is a step, and its branch names its children |
| Concurrent steps | bounded by what keeps the sequence predictable | native, in any shape Reactor allows |

**Partial progress survives.** Two branches run concurrently, one checkpoints, the process
dies: the next attempt fast-forwards the recorded branch and re-runs the other from where
it stood.

**In flight at halt time.** Reactor waits `halt_timeout` (5s by default) for async steps,
so those that finish get checkpointed. Steps still running past it are abandoned and run
again on the next attempt — at-least-once side effects, the boundary every durable engine
draws somewhere.

**Where order still bites.** `map` keys its generated steps by index, so its source has to
be stably ordered. A `map` over a read action with no `sort` can hand element 3 a
different record on the next attempt and replay the wrong checkpoint into it. Sorting the
source is the fix, and the contract below says so.

**Transactions.** An `Ash.Reactor` `transaction` block groups its steps into one database
transaction. When the store shares that repo, the checkpoints written inside commit with
it, so a step's effect and its checkpoint agree.

## The replay contract

- Step names are checkpoint keys. Renaming a step re-runs it.
- Arguments rebuild from upstream outputs and the workflow's inputs on every attempt, so
  nothing about them is persisted.
- Names generated by composite steps are stable across replays. `{:map, name, index}`
  and its siblings satisfy this, and a test pins it.
- A `map` source is stably ordered, since its generated names carry the index. A read
  action feeding one has a `sort`.
- Step outputs survive a `term_to_binary` round trip.
- A `where` guard may read anything. Its decision is recorded on first evaluation.

Reactor's DSL is declarative, so the shape of a workflow is fixed at compile time. The
contract covers the parts that stay dynamic.

## Actor and tenant

```elixir
Magma.start(MyApp.Checkout, %{order_id: id}, actor: current_user, tenant: org)
```

Both are snapshotted onto the workflow row as terms, and both are seeded into the reactor
context on every attempt. `Ash.Reactor` reads `context[:actor]` and `context[:tenant]`
directly, and a per-step `actor` entity keeps its precedence because it arrives as an
argument.

An actor is whatever the caller passes: a struct, a map, an id. Keeping the snapshot
small is the caller's lever — pass the minimum the workflow's steps read. Ash resources
are one option among several.

The snapshot fixes authority at the moment the workflow starts, so a workflow that waits
for days authorizes its later steps as the actor stood when it began. [Open
questions](#open-questions) carries the extension point for changing that.

## Waiting

### `await`

```elixir
await :confirmation, signal: "confirm", timeout: :timer.hours(48), block_ms: 5_000
```

1. A signal row is already present → consume it and return the payload.
2. Otherwise → write a waiter row, schedule the timeout job for any deadline, subscribe
   to PubSub, **re-check the store** to close the race, and block for up to `block_ms`.
3. A signal landing in the window returns it. An expired window halts the reactor.

```elixir
Magma.signal(workflow_id, "confirm", %{approver: "sam"})
```

The signal insert, the waiter lookup and the resume-job insert share one transaction.
The PubSub broadcast fires after commit. A wakeup survives a crash on the sending side.

A signal that arrives before its await is reached waits in its row until the await runs.

The worker reads the waiter row to learn why the reactor halted, so the halt handling
depends on committed state alone.

`on_timeout:` defaults to `:error`. `:return` yields `:timeout` for a `switch` to branch
on, which is the shape quote expiry wants.

### `poll`

```elixir
poll :settlement, every: :timer.seconds(30), until: &Provider.settled?/1
```

An unsatisfied check halts, and the worker returns `{:snooze, interval}`. This is the
case snooze fits: there is nothing to push you. Attempts hold no checkpoint; the
satisfying result does.

When several branches halt together, a poll wins and snoozes at the shortest interval.
A poll wake re-checks signals on the way through.

### Why the block window

A signal expected in seconds is common — a payment webhook, a fast provider callback.
Blocking for `block_ms` answers those without paying for a replay. Everything longer
releases the job, so a million waiting workflows cost a million rows and nothing else.

The block window holds an Oban concurrency slot, so `block_ms` and the queue's
concurrency are sized together.

## Outcomes

| Reactor returns | Oban gets | Status |
|---|---|---|
| `{:ok, result}` | `:ok` | `completed` |
| halted on `await` | `:ok` — the job completes and holds nothing | `waiting` |
| halted on `poll` | `{:snooze, n}` | `polling` |
| *(the process died)* | a retry on Oban backoff | `pending`, replays |
| `{:error, e}` past `max_retries` | `{:cancel, e}` | `failed`, unwound |

**A crash retries. An error unwinds.** Reactor already draws that line: `:retry` and
`max_retries` cover in-process retries, node death is invisible to Reactor and belongs to
Oban, and an `{:error, ...}` that survives both is the user declaring the run over.

## Unwinding

`Magma.Checkpointed.undo/4` marks `undone_at` on the step's checkpoint, in the same
transaction as the undo. Replay skips marked rows, so an undone step runs again. Marking
keeps the console's tape whole.

`compensate` returning `{:continue, value}` produces a result, and it checkpoints like
any other output.

## Resources

The store lives in the consuming application. Magma ships four resource extensions and
owns the contract; the app owns the modules, the domain, the tables and the migrations,
which puts the store inside whatever repo, multitenancy and policies the app already has.

| Extension | Resource holds |
|---|---|
| `Magma.Resource.Workflow` | module, inputs, actor, tenant, status, result, error, timestamps |
| `Magma.Resource.Checkpoint` | workflow, `sequence`, step name, output, error, `undone_at` |
| `Magma.Resource.Signal` | workflow, name, payload, `consumed_at` |
| `Magma.Resource.Waiter` | workflow, name, deadline |

Each extension injects the attributes, relationships, identities and actions that role
needs, so an app resource is the extension plus its `postgres do end` block.

Magma reads the roles off a domain, which is a place to look rather than a concept magma
claims. Any domain serves, including one the app already has:

```elixir
config :my_app, Magma,
  repo: MyApp.Repo,
  domain: MyApp.Workflows
```

`mix magma.install` writes the four resources as source into the app, wires the config,
and creates a domain for them when the app names none. Generated files stay readable and
editable in place, so customising a resource is an edit rather than an escape hatch.

`sequence` is a bigserial. Reactor runs steps concurrently, so the tape orders by
completion, and the step name is the lookup key.

Terms serialize with `:erlang.term_to_binary/2` into `bytea`, so atoms, tuples, structs,
Decimals and Ash records round trip exactly. A UI renders them through `inspect/2`.

Magma's own reads and writes pass `authorize?: false`, since they are engine bookkeeping
running beneath whatever policies the app puts on these resources.

## Modules

```
lib/magma.ex               start / await / signal / cancel — the public surface
lib/magma/dsl.ex           the Reactor extension: `magma do end`, await, poll
lib/magma/worker.ex        the one Oban worker
lib/magma/run.ex           decorate -> Reactor.run -> interpret the outcome
lib/magma/checkpointed.ex  the impl wrapper
lib/magma/middleware.ex    skip records, lifecycle, telemetry
lib/magma/step/await.ex
lib/magma/step/poll.ex
lib/magma/resource/        the four resource extensions
lib/magma/store.ex         role lookup, and every read and write against them
lib/magma/testing.ex
lib/mix/tasks/magma.install.ex
```

## Testing

The property that has to hold is that **a completed step never runs twice**, and the
suite is built to prove it.

| Area | Shape |
|---|---|
| Crash recovery | An ETS side-effect counter, a worker killed mid-run, `Oban.drain_queue`, and an assertion that each effectful step ran once. One case per phase boundary. |
| Checkpoint tapes | Pin the exact sequence a workflow produces, so an edit that adds, drops or reorders a step announces itself. |
| Generated names | Stability across `map`, `switch`, `compose`, `recurse`, `group`, `around` — the contract's most dynamic surface. |
| Concurrency | A workflow with parallel branches killed after one branch checkpoints, asserting the recorded branch replays and the other resumes. Plus checkpoints written from several Task processes at once. |
| Await races | A signal during the block window, before the await is reached, and after the halt. |
| Unwinding | Undo marks its checkpoint, and the replay after it re-runs the step. |
| Installation | `Igniter.Test` over `mix magma.install` against a bare app and against one that already has a domain, asserting it is idempotent on a second run. |

`Magma.Testing` sits over `Oban.Testing` in `:manual` mode so tests drain deterministically.

## Milestones

| | |
|---|---|
| 1 | **Scaffold** — mix project, ash / ash_postgres / reactor / oban / igniter / usage_rules, `mix usage_rules.sync`, the four resource extensions, `mix magma.install`, CI |
| 2 | **Durable core** — decoration, worker, `Magma.start/await`, and the first crash-recovery test green |
| 3 | **Waiting** — await, poll, signal, timeout jobs |
| 4 | **Unwinding** — undo marks, compensate, cancel |
| 5 | **Polish** — the `magma do end` section, `Magma.Testing`, docs |
| 6 | **`examples/fasset`** — a standalone app implementing the payout spec |

Milestone 2 decides whether the idea holds. The rest is surface.

## Open questions

Deferred until the milestone that meets them:

- **Child workflows.** Fasset dispatches a rail workflow from the payout spine and waits
  on it. `compose` covers the in-process case; a durable child with its own queue and its
  own Oban job is a milestone 6 question.
- **Cancellation of a waiting workflow.** A `waiting` workflow holds no job, so cancel
  writes a status and the next resume observes it. The interaction with unwinding is a
  milestone 4 question.
- **Retention.** Checkpoints accumulate. A pruning story arrives with milestone 5.
- **Actor rehydration.** The snapshot fixes authority at start time, which suits a
  workflow measured in minutes. A callback along the lines of `on_rehydrate/1`, run at the
  top of each attempt, would let an application reload the actor or re-check that it is
  still entitled. Added when a workflow long enough to need it turns up.
