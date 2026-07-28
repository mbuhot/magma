# Decisions

The design record. Each entry is a decision that shaped magma, why it went that way, and
what it rules out. Entries are appended; a reversal is a new entry naming the one it
replaces.

The full design lives in
[`docs/superpowers/specs/2026-07-29-magma-durable-workflows-design.md`](docs/superpowers/specs/2026-07-29-magma-durable-workflows-design.md).

---

## 1. Compose existing tools

Reactor supplies the DAG, the concurrency, the compensation and the undo. Oban supplies the
durable execution slot, the retry backoff and the scheduling. Ash supplies the store. Magma
is the decoration that ties the three together.

**Why:** every one of those is already load-bearing in an Ash application. A bespoke engine
would mean a second scheduler, a second retry policy and a second set of operational tools.

**Rules out:** a standalone workflow engine with its own executor.

---

## 2. Replay from the DSL, not from a persisted reactor

Every job attempt rebuilds the `%Reactor{}` from its module and replays recorded step
outputs. Nothing about the previous attempt persists except those outputs.

**Why:** a `%Reactor{}` holds step modules, options and closures, so serialising it is
fragile across deploys and impossible for a process that crashed before writing. Rebuilding
collapses the halt path and the crash path into one path.

**Costs:** a determinism contract on the workflow's shape — see [7](#7-a-step-is-identified-by-its-name).

---

## 3. Checkpoints are Ash resources owned by the application

Magma ships four resource extensions — `Workflow`, `Checkpoint`, `Signal`, `Waiter`. The
application owns the modules, the domain, the tables and the migrations. Config names a
domain and magma reads the roles off it. `mix magma.install` generates the resources as
source.

**Why:** the store inherits the app's repo, multitenancy and policies. A library-owned
resource cannot take a repo without compile-time config, and a library-owned domain
oversells what engine bookkeeping is.

**Rules out:** magma declaring its own Ash domain; a `use Magma.Domain` macro conjuring
resources at compile time.

---

## 4. Values persist as Erlang terms

`:erlang.term_to_binary/2` into `bytea`.

**Why:** atoms, tuples, structs, Decimals and Ash records round trip exactly, which is what
makes replay transparent. Most steps in an Ash workflow return Ash records, and JSON would
put an encoder between every step and its checkpoint.

**Costs:** checkpoints are opaque to SQL. `step_label` and a UI's `inspect/2` cover reading
them.

---

## 5. Waiting blocks briefly, then releases the job

An `await` blocks on PubSub for `block_ms` (~5s), then halts. The worker marks the workflow
`waiting` and the Oban job completes. `Magma.signal/3` writes the signal and inserts the
resume job in one transaction; the broadcast fires after commit.

**Why:** a webhook expected in seconds is answered without paying for a replay, and anything
longer costs one row and nothing else. Signal write and resume insert sharing a transaction
is what makes a wakeup unlosable.

**Rules out:** a snooze tier between the two. A snoozed job cannot be woken early, so it is
worse than halting on latency and worse than blocking on resources. `poll` covers the case
snooze suits — asking an API on an interval, where nothing will push you.

**Costs:** the block window holds an Oban concurrency slot, so `block_ms` and queue
concurrency are sized together.

---

## 6. Actor and tenant are snapshots

`Magma.start/3` takes `actor:` and `tenant:`, stores both as terms on the workflow row, and
seeds them into the reactor context on every attempt. `Ash.Reactor` reads `context[:actor]`
and `context[:tenant]`, and a per-step `actor` entity keeps precedence by arriving as an
argument.

**Why:** an actor is any term the caller chooses, so payload size is under their control and
an actor need not be an Ash resource.

**Costs:** authority is fixed at start time. An `on_rehydrate` callback is the extension
point, and it waits for a workflow long enough to need it.

---

## 7. A step is identified by its name

```elixir
step_key = :crypto.hash(:sha256, :erlang.term_to_binary(name, [:deterministic]))
```

**Why:** `%Reactor.Step{name: any}`, and composite steps generate tuples like
`{Reactor.Step.Map, outer, inner, index}`. `:deterministic` is load-bearing — the default
encoding varies through atom cache references and map key ordering, which would hash one
name two ways across attempts.

**Follows from it:** renaming a step re-runs it; reordering costs nothing, because the DAG
is the order; `(workflow_id, step_key)` unique makes the checkpoint write idempotent.

**Costs:** a `map` source must be stably ordered, since generated names carry the index.

---

## 8. Concurrency is untouched

Steps run concurrently and checkpoints commit in whatever order the work finishes. Replay is
a map lookup keyed by name; the DAG is re-derived by Reactor's planner.

**Why:** an engine that identifies a step by its position in a call sequence has to keep
that sequence predictable. Keying on names lifts the restriction entirely.

`sequence` on `Checkpoint` is a bigserial for the console's tape. Replay never reads it.

---

## 9. Interception is three decorations, applied before the run

`Magma.Run.decorate/1` rewrites the built `%Reactor{}` — wraps each step's `impl`, rewrites
its guards, prepends the middleware, seeds the context. Reactor's public API is the whole
interface.

Checkpoints load once per attempt into the context, so a step's lookup is a map read. Saves
happen per step, in whichever process ran it.

**Why:** no executor internals are reached into, and the planner still derives exactly the
graph the DSL describes.

---

## 10. A replayed value returns through the impl

`Reactor.Executor.Sync.maybe_store_undo/4` keeps a guard-skipped step off the undo stack.
Returning a recorded value from a prepended guard would therefore make every replayed step
silently un-undoable.

So replay comes back through the impl wrapper, which makes the step an ordinary success: it
lands on the undo stack, stores an intermediate result, and unwinds with everything else.

The user's own guards are **rewritten** rather than prepended to. An output on record forces
them to `:cont`; a skip on record forces `{:halt, recorded}`, reproducing the original skip
and correctly keeping it off the stack.

**Supersedes:** an earlier design that prepended a checkpoint guard.

---

## 11. A crash retries, an error unwinds

| Reactor returns | Oban gets | Status |
|---|---|---|
| `{:ok, result}` | `:ok` | `completed` |
| halted on `await` | `:ok` | `waiting` |
| halted on `poll` | `{:snooze, n}` | `polling` |
| *(the process died)* | a retry on backoff | `pending`, replays |
| `{:error, e}` past `max_retries` | `{:cancel, e}` | `failed`, unwound |

**Why:** Reactor already draws the line. `:retry` and `max_retries` cover in-process
retries, node death is invisible to Reactor and belongs to Oban, and an `{:error, ...}`
surviving both is the user declaring the run over.

---

## 12. A resumed rollback is driven from checkpoints

The first `undone_at` mark moves a workflow to `unwinding`, and it never re-enters
`Reactor.run` again. `Magma.Unwind` walks standing checkpoints newest-first by `sequence`,
resolves each step's arguments from the checkpoint map, calls `Reactor.Step.undo/4` and
marks the row.

**Why:** rebuilding the undo stack by replay and poisoning the first step that would do new
work cannot promise completeness — Reactor stops scheduling once the error propagates, so a
parallel branch that had yet to replay was never taken back.

**Falls out of it:** the marks are the rollback's progress log, so a crash mid-rollback
resumes exactly where it stopped, and cancelling a `waiting` workflow needs no replay at
all.

**Supersedes:** replay-then-poison, and the earlier claim that a durable rollback would need
its own row and job.

**Costs:** magma drives the undo loop rather than delegating to Reactor's executor. Reactor
keeps owning compensation and undo inside a live run.

---

## 13. Composite steps divide on where their children run

Reactor's composites split on one question, and magma treats the halves differently.

| Shape | Steps | Mechanism | Checkpoints |
|---|---|---|---|
| Inlining | `map`, `switch` | return `{:ok, value, steps}` into the outer plan | one per generated child; the parent holds none and re-plans |
| Nesting | `group`, `around`, `recurse`, `compose` | build a private reactor and call `Reactor.run/4` inline | one, for the composite as a whole |

**Why:** an inlining parent's children join the outer plan, so the wrapper decorates them on
the way out and each carries its own row. A nesting composite's children never reach the
outer plan and cannot be decorated, so the composite is a single step with a single
checkpoint.

**Costs:** a nesting composite re-runs its children together after a crash, and unwinds them
only within its own nested run. Effectful work needing its own checkpoint belongs in the
outer reactor or under a `map` or `switch`.

**Rejected:** `compose` with `support_undo?: true`. Its recorded value is `%{reactor:
reactor}` — a live `%Reactor{}` holding refs, closures and a Multigraph plan — because its
`undo/4` calls `Reactor.undo/2` on it. Decoration fails naming the step and the option.

**Supersedes:** an earlier entry claiming all six composites return `{:ok, value, steps}`,
and that `around` and `group` children needed resolving during a rollback.

---

## 14. A rollback of a rollback stays outside

A failed undo is collected and its checkpoint keeps standing, so what is still out there is
on the record.

---

## 15. Roles are read off the resources, so the domain declares nothing

`Magma.Store.resource/2` finds which resource plays which role by checking
`Spark.extensions/1` on each resource in the configured domain.

**Why:** the domain needed no extension of its own, which drops a module from the library and
a line from setup, and lets an application put magma's resources in a domain it already has.

**Supersedes:** the `Magma.Domain` extension the design called for.

---

## 16. The tape orders by primary key

`Checkpoint` has no `sequence` column. Its `id` is a UUIDv7, which embeds its timestamp.

**Why:** a bigserial would need a hand-edited migration. Ordering by `id` is correct for the
rollback too: a dependent step completes strictly after the one it reads, so a tie in the
same millisecond can only fall between independent steps, whose relative undo order does not
matter.

---

## 17. Waking a blocked wait rides on Oban's notifier

`Magma.Notifier` sends to a local `Registry` and publishes on `Oban.Notifier`.

**Why:** magma takes no pubsub dependency, and the reach is already cluster-wide. A missed
message costs nothing — the step re-checks the store before halting, and a halted workflow is
brought back by the resume job rather than by the broadcast.

---

## 18. `await` and `poll` are steps, not entities yet

Both are written as a plain `step` over `Magma.Step.Await` or `Magma.Step.Poll`.

**Why:** a custom Reactor entity needs its own target struct and a `Reactor.Dsl.Build`
implementation, since `Reactor.Dsl.Step` has no fields for `signal`, `block_ms` or
`on_timeout`. The step form has the whole behaviour and no new syntax to learn.

**Costs:** the DSL sugar the design showed is still to come.

---

## 19. An error ends the run, and only a crash brings it back

The worker returns `{:cancel, error}` on `{:error, ...}` and refuses to run a workflow that
has already ended.

**Why:** this is [11](#11-a-crash-retries-an-error-unwinds) in practice. Oban's `max_attempts`
covers process death alone. A step wanting another go asks Reactor for it with `:retry`,
which is where the retry policy belongs.
