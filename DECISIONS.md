# Decisions

The design record. Each entry is a decision that shaped magma, why it went that way, and
what it rules out. Entries are appended; a reversal is a new entry naming the one it
replaces.

The full design lives in
[the design spec](https://github.com/mbuhot/magma/blob/main/docs/superpowers/specs/2026-07-29-magma-durable-workflows-design.md).

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

`Magma.Run.decorate/2` rewrites the built `%Reactor{}` — wraps each step's `impl`, rewrites
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

The user's own guards are **rewritten** rather than prepended to: a step with a recorded
output forces them to `:cont`, so nothing can skip a step whose effect already happened.

A step a `where` skipped records nothing, so a guard that answers differently on a later
attempt lets the step run. No effect is repeated by that — there was none to repeat — but the
run diverges from the one before it. Recording skips would close it, and nothing does yet.

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

**`compose` with undo support:** its run step records `%{reactor: reactor}` — a live
`%Reactor{}` holding refs, closures and a plan — because its `undo/4` calls `Reactor.undo/2`
on it. That step is left uncheckpointed and its nested reactor re-runs; the extract step
beside it carries the composed result. Refusing it outright was wrong, since
`support_undo?` defaults to `true` and the refusal blocked every ordinary `compose`.

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

## 18. `await` and `poll` are entities

Both are `Spark.Dsl.Entity` structs of their own, patched into Reactor's `reactor` section
and implementing `Reactor.Dsl.Build` to add the matching step.

**Why:** they carry options `Reactor.Dsl.Step` has no fields for — `signal`, `block_ms`,
`on_timeout`, `until`, `every` — so borrowing its target was never going to work. Owning the
struct also lets each validate its own options at compile time.

Both are still ordinary nodes in the graph. They take arguments, downstream steps read their
result, and `wait_for` orders them.

**Costs:** two structs and two protocol implementations to keep alongside Reactor's own.

---

## 19. An error ends the run, and only a crash brings it back

The worker returns `{:cancel, error}` on `{:error, ...}` and refuses to run a workflow that
has already ended.

**Why:** this is [11](#11-a-crash-retries-an-error-unwinds) in practice. Oban's `max_attempts`
covers process death alone. A step wanting another go asks Reactor for it with `:retry`,
which is where the retry policy belongs.

---

## 20. A child workflow is adopted by a derived id

`Magma.Step.Dispatch` runs another workflow as a durable child — its own row, its own Oban
job, its own queue — and waits for its result. The child's id comes from
`Magma.Key.child_id/2`, a digest of the parent's id and the dispatching step's name.

**Why:** the id has to be stable so a replay finds the child already running rather than
starting a second one. Everything else can move, which is the point: the *module* is resolved
at run time, from config or from an argument, while identity stays fixed. A spine can route
to a rail it does not name.

**How the result comes back:** the child records its parent and the signal to answer on. The
worker signals that parent when the child ends, either way, so the parent's wait is answered
by the same mechanism a webhook uses. A child that fails fails its parent.

**Costs:** a workflow row is a UUIDv7, so the digest sets the version and variant bits to
stay a well-formed one.

---

## 21. A step with no undo is skipped, not raised at

`Magma.Unwind` checks `Reactor.Step.can?(step, :undo)` and leaves the checkpoint standing when
the answer is no.

**Why:** Reactor's executor never put such a step on its undo stack either. Calling `undo/4`
on a step that does not implement it raised.

**What it enables:** a workflow carried forward rather than reversed. An onboarding a provider
has partly decided is the thing a resumed run needs, and tearing the account down would cost
the customer every document already sent. Declaring no `undo/4` is how a workflow says so.

---

## 22. An unresolvable checkpoint is reported, not raised

A checkpoint whose step `Magma.Unwind` cannot resolve — a child an inlining composite
generated at run time — is logged and left standing, and the rollback finishes without it.

**Why:** returning it as an error held a rollback open that had otherwise finished, leaving
the workflow stuck in `cancelling` forever. What is still out there belongs on the record, not
in the way.

**Costs:** work in a `map` or `switch` branch is not taken back. Materialising those children
by driving their parent is the fix, and it is still to come.

---

## 23. A rollback claims a checkpoint before undoing it

`Magma.Unwind` marks `undone_at` conditionally, on the row still being unmarked, before
calling `undo/4`. A claim it loses means another rollback has that step. A failed undo gives
the claim back, so the checkpoint still stands.

**Why:** two jobs for one workflow can run at once — a signal resume and a child-completion
resume, say. Both read the same standing rows and both called `undo/4`, so a ledger was
credited twice. Forward progress had the unique index for this. Rollback had nothing.

**Costs:** a crash between the claim and the undo leaves a step marked that was never taken
back. The mark is the progress log, so that step is treated as done and its work stands. A
claim carrying a lease, rather than a plain mark, is what would close it.

---

## 24. A halting step refuses to run inside a nesting composite

`await`, `poll` and `dispatch` check that the step Reactor is running is one magma wrapped, and
raise a message naming the step and the composite it sits inside when it is not.
`Magma.Checkpointed` puts the step it wraps into the context as `:magma_step`, and comparing
that to `:current_step` is the check.

**Why:** a nesting composite — `group`, `around`, `recurse`, `compose` — calls `Reactor.run/4`
on a private reactor whose steps magma never sees. `{:halt, _}` from a step in there becomes
`{:halted, %Reactor{}}` as the composite's own result, which Reactor rejects as an invalid
result, so the workflow failed with a page of struct rather than an explanation.

**What else it closes:** `Reactor.Step.Recurse` builds every continuation with the same step
name, so a `dispatch` in a recursed reactor derived one child id for every iteration. Iteration
two adopted iteration one's finished child and waited on a signal already consumed. There is
nothing deterministic in the inner reactor's context that distinguishes an iteration, so a
correct id could not be derived.

**Costs:** waiting inside a loop is expressed by a `map` over the work, or by a child workflow
that does the looping. A `recurse` in a workflow that waits stays a pure one.

---

## 25. A dispatched child's failure unwinds its caller

`Magma.Step.Dispatch` surfaces a child's error as the dispatching step's own failure, so the
caller cannot treat a child's failure as data and carry on.

**Why:** a step's return is the only channel Reactor gives a caller, and an `{:error, _}`
there is defined to end the run — [11](#11-a-crash-retries-an-error-unwinds) applies to a
dispatched child exactly as it applies to any other step.

**What it means for a workflow:** a child whose failure is an expected outcome returns it as
a value instead. `Agency.Sale.Conditions` does exactly this: a declined finance comes back as
`%{outcome: :condition_failed, kind: …}` so the attempt can refund, write the commission back
and open the next generation.

---

## 26. Alternative signals need one await and a switch

Two sibling awaits waiting on different signal names both park, and a reactor cannot finish
with one of them unresolved, so only one of the two can ever arrive.

**Why:** magma has no construct for "wait for whichever of these signals lands first and
cancel the other" — each `await` is its own node the plan must complete.

**What it means for a workflow:** mutually exclusive events share a signal name and are
distinguished by payload. `Agency.Sale.Attempt` awaits `"settlement.completed"` once and
switches on the payload to separate a completed settlement from a buyer default.

---

## 27. A checkpoint decodes without the atom-table guard

`Magma.Type.Term` decodes stored checkpoints with `:erlang.binary_to_term/1`, not the
`:safe` option.

**Why:** `:safe` refuses to create an atom absent from the running VM's atom table, and a
step module reaches the VM only when something loads it. Reactor modules name their steps as
compile-time DSL arguments, so building a workflow's `%Reactor{}` does not load every step
module, and Elixir's lazy loading in dev and test leaves plenty of modules unloaded until
something calls into them directly. A checkpoint written on an attempt that did load a step,
read back on a later attempt that replays instead of running it, can hold an atom the second
attempt's VM has never created — and `:safe` turned that into an unresolvable checkpoint over
data the application itself wrote. A checkpoint row is the application's own write into its
own table, not a channel an outside party feeds. `:safe` defends against a poisoned row
exhausting the atom table, but anyone able to write checkpoint rows already controls what a
replayed step returns, and every step downstream of a replay trusts that return value
completely — so the guard buys little against a threat the design does not have, at the cost
of breaking valid data.

**Costs:** a corrupt checkpoint binary still fails to decode and `cast_stored/2` still
reports `:error` rather than raising, but nothing now stops a checkpoint holding an atom from
growing the atom table on every distinct value a run stores.

---

## 28. A dispatched child's outcome is read from the child

`Magma.Step.Dispatch` derives the child's id, adopts a child already there, and asks where it
stands. A child in a terminal state is answered from its own row — `result` on a `completed`
one, `error` on a `failed` or `cancelled` one. The report signal is a wake-up.

**Why:** a signal is consumed destructively and read once. A parent that fans out
concurrently takes a failing child's report, returns `{:error, _}` from that element, and gets
that error dropped: Reactor's async executor prefers a sibling's halt over an error raised in
the same batch, and an error is not checkpointed. The next attempt re-ran the element against a
child whose only account of itself had already been spent, so the parent parked on a report
that would never come again and stayed there.

**Falls out of it:** the terminal read is reached only in recovery — a first attempt starts the
child and waits, and an element that resolved carries a checkpoint — so the ordinary path pays
for nothing. An element answered from the row consumes any report still pending and gives up
the wait, so a parent answered another way holds nothing.

**Both paths give the same account.** A step failure that nothing can compensate is written to
the workflow's row by `Magma.Middleware` as the failure happens, before the rollback it triggers
takes anything back. A rollback resumed by a later attempt therefore ends the workflow carrying
that error, and `Magma.Worker` reports it to the parent from there as the ordinary failure path
would have. Whichever way `Magma.Step.Dispatch` resolves — the report or the row — it wraps what
it read in a `Magma.ChildError` carrying the child's id, its module and its own error, so a
parent's failure names the child that died and the inner error stays reachable as a field. A
chain of dispatches nests one inside the next, and the outermost message reads down to the
cause.

**Costs:** an extra write on the failing path, and two shapes of stored error — the ordinary
ending records what `Reactor.run/4` returned, a resumed rollback keeps the step error the
middleware saw. The write is skipped for a step that can compensate, since its failure may yet
be recovered, so a rollback resumed after a compensation itself failed is what the
`compensate_error` event covers.

---

## 29. Every wait ready to park parks on the same attempt

`await` and `poll` are async steps, and a run's concurrency pool is sized to hold every wait its
reactor declares on top of the ordinary one.

**Why:** a halt stops the executor at the first halted step, and Reactor abandons whatever else
was in flight. Run the waits synchronously and exactly one of them parks per attempt: the
workflow's row then claims to be waiting on one name when the graph says it waits on four, the
three unparked ones hold no deadline, and a `poll` that never got its turn holds no job to bring
it back. A wait writes its waiter row before it blocks, so a wait that started has parked —
which makes starting them all in one batch the whole of the fix. The pool is what decides how
many start, and a parked wait holds no scheduler, so magma sizes the pool for them rather than
leaving a wide graph to the scheduler count.

**Falls out of it:** four solicitors' documents can arrive in any order, each wait's timeout runs
from the same instant, and a `poll` beside an `await` still snoozes the job.

**Costs:** waits generated at run time — inside a `map`, or by a `switch` branch — are not
counted, since the pool is sized from the declared steps. A graph that fans out more waits than
that at once parks what fits and reaches the rest on a later attempt.

---

## 30. A signal brings back a parked workflow whatever it is parked on

`Magma.signal/3` enqueues the resume job for any workflow that is parked, and for any workflow an
attempt presently holds — rather than only for one parked on that name. A job already waiting its
turn is the one case that needs nothing, since it starts after the delivery commits and reads it
for itself. The workflow's row is read `FOR UPDATE`, and an attempt holds that same row for as
long as it runs (§33), so a delivery and an attempt cannot each act on what the other is about to
write.

**Why:** what a run is waiting for is not knowable from outside it. The wait a signal answers may
be one the run has not reached, one it is parking on as the signal commits, or one a later
attempt will reach — and a delivery that asked "are you parked on this?" first was dropped in
every one of those cases, leaving an unconsumed signal against a workflow with no job. Nothing
ever came for it: a click that did nothing, forever, with no error.

**Falls out of it:** an attempt drains every signal it can reach, so waits are answered in
whatever order they are told in. A resume job is deduplicated against one already waiting its
turn, since that job stands for every delivery made before it starts.

**An attempt under way is no use to a delivery landing now.** It may already be past the wait that
wanted it: an attempt is one pass over the graph, and each `await` reads the store at the moment
its step runs. So the delivery sends a job of its own rather than trusting the pass in flight —
which is why uniqueness against an `executing` job would lose the wake-up, and why the job it
sends waits its turn instead.

**Costs:** a workflow parked on a name nothing will ever deliver is still woken by every other
signal it is told, and pays a replay for each.

---

## 31. Engine writes settle their own races

`consume_signal` is conditional on the signal being untaken, `release` treats a waiter another
attempt already cleared as the outcome it asked for, and `record` hands the loser of a checkpoint
collision the row that won.

**Why:** two attempts of one workflow overlap — a scheduled deadline firing beside a resume, an
async wait outliving the attempt that halted. Read-then-write against a shared row raised
`StaleRecord` out of the middle of a step, which Reactor read as a step failure and unwound the
whole run; a signal read twice answered two attempts with one delivery. Each of these writes now
says what happens when it loses, and the loser carries on with what stands.

**Falls out of it:** both attempts see the same output for a step, because the unique index picks
the recording and the other attempt reads it back rather than carrying its own.

**Costs:** an attempt that loses a checkpoint race has already done the step's work, so its
effect happened twice — the at-least-once boundary, reached here by overlap rather than by a
crash.

---

## 32. What is left of two attempts running at once

The claim (§33) holds a workflow to one attempt per job. What it does not hold is work Reactor
left running: the executor stops at the first halted step and its halt branch does not collect
what is still in flight, and those steps are started with `Task.Supervisor.async_nolink/5`, so
they are not linked to the job process. An async step can still be running after the run returned
`{:halted, _}`, after the workflow parked, and after the claim was given back — beside the attempt
that comes next.

**What holds anyway.** Every engine write says what happens when it loses (§31), the unique index
keeps one recording per step, and an ending stands whatever a slower attempt goes on to do.

**What it costs.** A step's effect can happen twice: the abandoned step and the next attempt both
run it, and one of them loses the recording after its work is already done. That is the
at-least-once boundary every durable engine draws somewhere.

**What would close it.** Reactor collecting its running tasks on the halt path as it already does
on the timeout path. Until then, a step whose effect cannot be repeated wants an idempotency key
of its own.

---

## 33. One attempt holds a workflow, and the rest wait their turn

An attempt claims the workflow's row — `claimed_at` and the id of the job holding it — with a
conditional update, and gives it back when it has written where the run stands. A job that finds
the workflow held returns `{:snooze, 1}`.

**Why:** two jobs for one workflow both find no checkpoint for a step, both run it, and the unique
index picks one of the two recordings after both effects have happened. That is how the agency
example came to hold two of the same compliance document. A signal that lands mid-attempt has to
send a job of its own (§30), so the jobs exist whether or not they should run together — the claim
is what makes the extra one wait rather than race.

**Why snooze rather than uniqueness at insert.** `Oban.Engines.Basic.snooze_job/3` raises the job's
ceiling as it reschedules, so a job can yield as often as it needs to for nothing. Refusing the
insert instead would throw away the wake-up it carries.

**A claim is free three ways:** nobody holds it, the lease on it has lapsed, or the job asking is
the job already holding it — a retry of a crashed attempt takes its own claim straight back rather
than waiting the lease out.

**The lease is the one number to get right.** `Magma.Api.lease_ms/1` reads it from the workflow's
own `magma` section, then `config :magma, lease_ms: ...`, then five minutes. It has to outlast the
longest attempt the workflow makes: too short and a second attempt starts beside a running one,
too long and a workflow whose attempt died sits idle for the difference. Align it with
`Oban.Plugins.Lifeline`'s rescue window so the two agree about when an attempt is dead.

**Costs:** two attributes on the application's workflow resource, so an application that has
already run `mix magma.install` regenerates its migrations. A claim released on the way out of an
attempt is a second write on every ending. And a job driven straight from a test carries no id, so
it cannot recognise a claim as its own — every such job would recognise every other one's.
