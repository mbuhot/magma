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
- [Interception](#interception)
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

The spelling depends on the entity, and both forms compile to `Reactor.Argument`s that
draw the same edges in the DAG:

| Entity | Wiring |
|---|---|
| `step` | `argument`, `wait_for` |
| An `Ash.Reactor` action — `read_one`, `update`, `create`, … | `inputs` for the action's params, `initial` for the record it acts on, `actor`, `tenant`, `context`, `load`, `wait_for` |

An action step has several kinds of dependency to keep apart, so it names each one. A
plain step has one kind and calls it `argument`. The template functions are shared, and
`argument` is absent from the action entities.

Magma's `await` is a plain Reactor step, so it takes `argument` and `wait_for`.

Magma adds no state channel of its own, and that omission is what makes replay work:

> **Arguments hold no checkpoint. Outputs do.**

On every attempt each step's arguments are rebuilt from the recorded outputs of the steps
upstream and the inputs on the workflow row, so they are identical by construction. A
step whose output is already recorded is skipped whatever its arguments say, so argument
transforms matter only for steps still to run.

One `Magma.Worker` carries the reactor module in its args, so no worker module is
generated per workflow and `Reactor.Info` supplies the rest.

### What magma adds

Three DSL entities: the `magma` section, `await`, and `poll`. Every existing entity keeps
its meaning, and a reactor written without magma runs under it as it stands —
`Magma.start/3` accepts a plain `use Reactor` module, because the decorations happen at
run time on the built `%Reactor{}`.

Alongside them comes a contract over constructs that already exist:

| Construct | Under magma |
|---|---|
| Step outputs | survive a `term_to_binary` round trip |
| Step names | are durable identifiers, stable across deploys |
| `map` sources | are stably ordered |
| `where` guards | keep the answer they gave the first time |

That last row is the one deliberate change in evaluation, and it surfaces on replay
alone. A guard reading the clock or the database gave an answer that has already been
acted on, so magma holds it to that answer.

## Interception

### Where it hooks

`Magma.Run.decorate/1` rewrites the built `%Reactor{}` before handing it to
`Reactor.run/4`. Reactor's public API is the entire interface; no executor internals are
reached into.

```elixir
%Reactor{reactor |
  middleware: [Magma.Middleware | reactor.middleware],
  context: Map.merge(reactor.context, %{actor: actor, tenant: tenant, magma: run_state}),
  steps: Enum.map(reactor.steps, &decorate_step/1)
}
```

```elixir
%Step{step |
  impl: {Magma.Checkpointed, magma_inner: step.impl, magma_name: step.name},
  guards: Enum.map(step.guards, &neutralise/1)
}
```

`arguments` are left alone, so the planner derives exactly the graph the DSL describes.

### Step identity

A step is identified by its `name`, and `%Reactor.Step{name: any}` means that is an
arbitrary term:

| Origin | Name | Unique because |
|---|---|---|
| `step :charge_card` | `:charge_card` | Spark's `identifier: :name` rejects duplicates at compile time |
| `map` children | `{Reactor.Step.Map, outer_name, inner_name, index}` | it carries the outer step's name and the element index |
| `compose` | `{:compose, name}` | it carries the call site's name, so one sub-reactor composed twice yields two identities |
| `Reactor.Builder` at run time | whatever the caller passes | the unique index below turns a collision into a loud error |

So the key is derived rather than stored as text:

```elixir
step_key = :crypto.hash(:sha256, :erlang.term_to_binary(name, [:deterministic]))
```

`:deterministic` is what makes this work. The default encoding may vary between runs
through atom cache references and map key ordering, which would hash the same name two
ways across attempts. The canonical encoding gives one answer.

Hashing gives a fixed 32 bytes for a term of unbounded size. `step_label`, an
`inspect(name, limit: :infinity)`, rides alongside for the console and for SQL debugging,
and display is its only job — replay hashes the live step's name and never reconstructs
the recorded one.

`(workflow_id, step_key)` is unique, which earns its place twice: it is the replay lookup,
and it makes the checkpoint write idempotent, so two processes racing to record one step
collide loudly.

Nothing else enters identity. `step.ref` is a `make_ref/0`, fresh in every process and
every attempt, and the plan position, impl module and arguments are all free to move.

### What the executor does with a step

`Reactor.Executor.StepRunner.run/4` runs three things in order: assemble arguments from
`intermediate_results` and the reactor's inputs, `evaluate_guards/4`, then
`Reactor.Step.run/3` dispatching to `impl`. Magma sits in the last two.

| Record for this step | Guards | Impl | The executor sees |
|---|---|---|---|
| an output | forced to `:cont` | returns the recorded value | an ordinary success |
| a skip | forced to `{:halt, recorded}` | never called | `{:skip, …}` |
| none | the user's own answer | the inner impl runs, and its output is written | whatever happened |

### Why replay returns through the impl

`Reactor.Executor.Sync.maybe_store_undo/4` reads:

```elixir
cond do
  MapSet.member?(state.skipped, step.ref) -> reactor
  Step.can?(step, :undo) -> %{reactor | undo: [{step, value} | reactor.undo]}
  true -> reactor
end
```

A guard-skipped step is left off the undo stack. That is right for `where` — a step that
never ran has nothing to take back — and wrong for replay, where a step that ran on an
earlier attempt has plenty.

So a replayed value comes back **through the impl**, which makes the step an ordinary
success: it lands on the undo stack, it stores an intermediate result, and a failure later
in the run unwinds it like any other completed work.

Neutralising the user's guards is what protects that. With an output on record they are
forced to `:cont`, so nothing skips a step whose effect has already happened. With a skip
on record they are forced to `{:halt, recorded}`, which reproduces the original skip and
correctly keeps it off the undo stack.

### The wrapper's other jobs

- Delegates `can?`, `async?`, `nested_steps` and `backoff` to the inner impl, decorating
  nested steps on the way through.
- `undo/4` delegates, then marks `undone_at` on the checkpoint, in one transaction.
- `compensate/4` delegates. A `{:continue, value}` is a result, so it checkpoints.
- A step returning `{:ok, value, steps}` holds no checkpoint and has its returned steps
  decorated.

### Middleware

Writes skip records from `{:guard_fail, guard, result}`, and carries workflow lifecycle
and telemetry. Its `event/3` returns `:ok` and can only observe, which is why the
checkpoint write lives in the impl where a failure can fail the step. A lost skip record
costs one re-evaluation of a guard.

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

### What Reactor already does

Two mechanisms, aimed at different steps:

- `compensate/4` runs on the step that **failed**, to recover it. `{:continue, value}`
  turns the failure into a success, `:ok` lets the error stand and starts the rollback,
  `:retry` re-runs the step.
- `undo/4` runs on steps that **succeeded**, newest first, to take their work back. A
  successful step joins `reactor.undo` when it answers `can?(step, :undo)`. Each undo
  retries up to five times before `UndoRetriesExceededError`, and an `{:error, _}` is
  collected while the rollback carries on.

`undo/4` receives the step's original arguments, rebuilt from upstream results by the same
machinery replay leans on. So an undo that follows a replay sees the arguments the first
run saw.

### What magma adds

The wrapper sits on both callbacks and writes what happened:

| Callback returns | Wrapper | Checkpoint |
|---|---|---|
| `compensate` → `{:continue, value}` | delegates, then records | written, since the step succeeded |
| `compensate` → `:ok`, `:retry`, `{:error, _}` | delegates | untouched, since the step never succeeded |
| `undo` → `:ok` | delegates, then marks | `undone_at` set, inside the undo's transaction |
| `undo` → `{:error, _}` | delegates | left as it stands, recording that the work is still out there |

### Four walks

**An error, no crash.** A and B complete, C fails. C compensates; failing that, Reactor
undoes B then A, marking each. The worker hands Oban `{:cancel, error}`, and the workflow
ends `failed` with its work taken back.

**An error on a later attempt.** Attempt 1 checkpoints A and B, then the process dies.
Attempt 2 replays A and B through the impl, so both land on the undo stack; C runs and
fails; B and A undo for the first time. This walk is the reason replay returns through the
impl.

**A crash during the unwind.** B's undo commits its mark, then the process dies before A's
runs. A crash is a retry, so the next attempt replays — and B, marked undone, is absent
from the replay map, so **B runs again**, fails at C again, and both undo. B's effect is
redone and taken back rather than left half-way: at-least-once, applied to undo.

**A step that cannot be undone.** A step without `undo/4` never joins the stack and is
never taken back. Its effect stands and the workflow ends `failed`. This is where a
transfer that may already have moved money belongs, parked and alerted rather than
reversed.

### Cancelling a workflow that is waiting

A `waiting` workflow holds no process and no job, so there is no live reactor to unwind.

`Magma.cancel/1` writes `cancelling` and inserts a resume job. The worker decorates as
usual and puts a cancel flag in the context, and the wrapper returns
`{:error, %Magma.Cancelled{}}` from the first step that finds no checkpoint. Everything
already recorded has replayed onto the undo stack by then, so Reactor unwinds it with the
machinery it already has and the workflow ends `cancelled`.

Cancellation is therefore replay plus one poison pill, and it needs no second rollback
engine.

### Where unwinding stops

An unwind lives inside one attempt. A crash part way through restarts it by replay, which
costs the redo in the third walk above. Checkpointing each undo so a rollback resumes
where it stopped is the shape of a separate compensation workflow, and it stays outside
this design.

## Resources

The store lives in the consuming application. Magma ships four resource extensions and
owns the contract; the app owns the modules, the domain, the tables and the migrations,
which puts the store inside whatever repo, multitenancy and policies the app already has.

| Extension | Resource holds |
|---|---|
| `Magma.Resource.Workflow` | module, inputs, actor, tenant, status, result, error, timestamps |
| `Magma.Resource.Checkpoint` | workflow, `sequence`, `step_key`, `step_label`, output, error, `undone_at` |
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
| Crash mid-unwind | A process killed between two undos, asserting the next attempt redoes the marked step and takes both back. |
| Cancelling a wait | A `waiting` workflow cancelled, asserting every recorded step is undone and the workflow ends `cancelled`. |
| Undo after replay | A run that replays step A from a checkpoint and then fails at step B, asserting A's undo ran. This is what pins replay to the impl path, since a guard-skipped step never reaches the undo stack. |
| Guard neutralisation | A `where` that answers differently on the second attempt, asserting a completed step stays completed and a skipped step stays skipped. |
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
- **Retention.** Checkpoints accumulate. A pruning story arrives with milestone 5.
- **Actor rehydration.** The snapshot fixes authority at start time, which suits a
  workflow measured in minutes. A callback along the lines of `on_rehydrate/1`, run at the
  top of each attempt, would let an application reload the actor or re-check that it is
  still entitled. Added when a workflow long enough to need it turns up.
