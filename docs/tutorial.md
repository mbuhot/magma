# Magma, in one sitting

Durable workflows: what they are, how to write one, and what the database looks like at each
point. Every `psql` block below is real output from `examples/payouts`.

## The problem

A payout touches five systems and takes two days. Somewhere in the middle the node restarts.

| Question | Without durability |
|---|---|
| Was the customer already debited? | read your own tables and guess |
| Was the quote they saw the one you charged? | re-price and hope |
| Did the provider already get this transfer? | call them and reconcile |
| A rejection came back — who gives the money back? | a script someone writes later |

## The intuitive model

Think of two things: **a recipe and a ledger.**

The **recipe** is your workflow module. It is code, and it is re-read from source on every
attempt. Nothing about the run is serialised into the database — no continuation, no program
counter, no half-built graph.

The **ledger** is one row per step, holding what that step returned. A row appears the moment
a step succeeds, before the next step starts.

Running a workflow means: **start at the top, every time.** A step that already has a ledger
row does not run — it hands back the value it returned the first time and the run moves on. A
step with no row does the work.

```
attempt 1     transfer ✓      quote ✓      await ⏸  ← the job ends here, the process is gone
ledger        [:transfer]     [:quote]     —

              ────────────── two days pass ──────────────
              a signal arrives, and a new job is enqueued

attempt 2     transfer ↺      quote ↺      await ✓      debit ✓
              replayed        replayed     new work     new work
```

Three things fall out of that, and they are the whole point.

**Nothing is ever done twice.** The customer is debited once because the second attempt finds
`:debit` in the ledger and skips it.

**Waiting is free.** The workflow parked at `await` holds no process, no job and no memory —
it is a row and a scheduled wakeup. A forty-eight hour wait costs nothing.

**A crash is not special.** Losing the node is the same event as any other attempt boundary.
There is no recovery path to write, because recovery *is* the normal path.

The price of admission is that a step's job is to **do one thing and return a value that
describes what it did**. If a step does something the ledger cannot capture, replay cannot
protect it.

## The four parts

| | Supplies |
|---|---|
| **Reactor** | the recipe — a DAG, concurrency, compensation and undo |
| **Oban** | the durable execution slot, retry backoff, scheduling |
| **Ash** | the ledger, as resources your application owns |
| **Magma** | the decoration that ties them together |

```elixir
def deps, do: [{:magma, github: "mbuhot/magma"}]
```

```sh
mix igniter.install magma
mix ecto.migrate
```

That writes four resources into a domain of your own and points magma at them.

| Table | Holds |
|---|---|
| `magma_workflows` | one row per run: module, inputs, actor, status, result |
| `magma_checkpoints` | the ledger — one row per completed step |
| `magma_signals` | events delivered from outside, consumed once |
| `magma_waiters` | what a parked workflow is waiting for, and until when |

They are ordinary Ash resources in your own domain, so adding a policy or an attribute is an
edit.

## A workflow

An ordinary Reactor with one extra extension.

```elixir
defmodule Payouts.Workflows.Payout do
  use Reactor, extensions: [Magma.Dsl]

  magma do
    queue :payouts
  end

  input :transfer_id

  step :transfer, Steps.LoadTransfer do
    argument :transfer_id, input(:transfer_id)
  end

  step :quote, Steps.Quote do
    argument :transfer, result(:transfer)
  end

  await :confirmation do
    signal "confirm"
    timeout :timer.minutes(15)
    argument :quote, result(:quote)
  end

  step :debit, Steps.Debit do
    argument :transfer, result(:transfer)
    argument :confirmation, result(:confirmation)
  end

  step :rail, {Magma.Step.Dispatch, workflow: &Payouts.Routing.rail_for/2, ...} do
    argument :transfer, result(:transfer)
    argument :quote, result(:quote)
    wait_for :debit
  end

  await :settlement do
    signal "settlement"
    timeout :timer.hours(24)
    wait_for :rail
  end

  step :settle, Steps.Settle do
    argument :transfer, result(:transfer)
    argument :settlement, result(:settlement)
  end

  return :settle
end
```

State flows through Reactor's own templates — `input/1` and `result/1`. Magma adds no state
channel, and that is what makes replay work: **arguments hold no checkpoint, outputs do.** Each
attempt rebuilds a step's arguments out of the ledger and the workflow's inputs, so what a
replayed step is handed is what it was handed the first time, by construction.

```elixir
{:ok, workflow} = Magma.start(Payouts.Workflows.Payout, %{transfer_id: transfer.id})
```

---

Two runs produced everything below. **Ada**'s payout is rejected at settlement (points A, B,
E). **Bea**'s survives a replay and completes (points C, D). Ids are truncated to eight
characters.

## Point A — parked at the confirmation

Ada has 100,000 cents and asks for 25,000 out. Two steps run, then the workflow reaches
`await` and stops.

```sql
select left(id::text, 8) as id, split_part(module, '.', 3) as module, status
from magma_workflows order by id;
```
```
    id    |  module   | status
----------+-----------+---------
 019fab9b | Workflows | waiting
```

```sql
select c.step_label, c.output is not null as has_output, c.undone_at is not null as undone
from magma_checkpoints c order by c.id;
```
```
 step_label | has_output | undone
------------+------------+--------
 :transfer  | t          | f
 :quote     | t          | f
```

The ledger, two rows deep. `:confirmation` has no row, so that is where the next attempt
starts doing work.

```sql
select name, kind, deadline from magma_waiters order by id;
```
```
  name   |  kind  |          deadline
---------+--------+----------------------------
 confirm | signal | 2026-07-29 02:16:37.660861
```

```sql
select id, queue, state, attempt, scheduled_at from oban_jobs order by id;
```
```
 id |  queue  |   state   | attempt |        scheduled_at
----+---------+-----------+---------+----------------------------
  1 | payouts | completed |       1 | 2026-07-29 02:01:37.487101
  2 | payouts | scheduled |       0 | 2026-07-29 02:16:37.660861
```

Read that last table carefully — it is the claim about waiting being free, in evidence. Job 1,
which ran the workflow, is **completed**. Nothing is executing. All that exists is a row, a
waiter, and job 2 scheduled at the fifteen-minute timeout.

```sql
select c.name, c.balance_cents, t.status as transfer_status
from customers c join transfers t on t.customer_id = c.id;
```
```
 name | balance_cents | transfer_status
------+---------------+-----------------
 Ada  |        100000 | requested
```

Her money has not moved. The quote was taken; nothing was charged.

## Point B — confirmed

```elixir
Magma.signal(workflow.id, "confirm", %{confirmed_by: "ada"})
```

The signal row and the job that wakes the workflow commit in one transaction, so a crash on the
sending side cannot leave a parked workflow with nothing coming for it.

```sql
select left(id::text, 8) as id, split_part(module, '.', 3) as module, status, parent_signal
from magma_workflows order by id;
```
```
    id    |  module   |  status   |   parent_signal
----------+-----------+-----------+-------------------
 019fab9b | Workflows | waiting   |
 247d5158 | Rails     | completed | magma.child.:rail
```

A second workflow. `Magma.Step.Dispatch` resolved EUR to `Payouts.Rails.Bridge` and started it on
the `rails` queue as a child — its own row, its own ledger, reporting back through the signal
`magma.child.:rail`.

```sql
select left(w.id::text, 8) as workflow, c.step_label, c.output is not null as has_output
from magma_checkpoints c join magma_workflows w on w.id = c.workflow_id order by c.id;
```
```
 workflow |  step_label   | has_output
----------+---------------+------------
 019fab9b | :transfer     | t
 019fab9b | :quote        | t
 019fab9b | :confirmation | t
 019fab9b | :debit        | t
 247d5158 | :fund         | t
 247d5158 | :send         | t
 019fab9b | :rail         | t
```

The wait itself is a checkpoint — `:confirmation` holds the signal payload, so a later attempt
never waits for that signal again.

```sql
select name, kind, deadline from magma_waiters order by id;
```
```
    name    |  kind  |          deadline
------------+--------+----------------------------
 settlement | signal | 2026-07-30 02:01:44.284374
```

The waiter swapped. `confirm` is gone; the spine is parked on `settlement` now.

```sql
select left(workflow_id::text, 8) as workflow, name,
       consumed_at is not null as consumed, inserted_at
from magma_signals order by id;
```
```
 workflow |       name        | consumed |        inserted_at
----------+-------------------+----------+----------------------------
 019fab9c | confirm           | t        | 2026-07-29 02:03:02.459212
 019fab9c | magma.child.:rail | t        | 2026-07-29 02:03:02.613871
 019fab9c | settlement        | t        | 2026-07-29 02:03:15.303046
```

Signals are rows too, consumed once. (This is Bea's run, showing all three she received.)

```sql
select c.name, c.balance_cents, t.status as transfer_status
from customers c join transfers t on t.customer_id = c.id;
```
```
 name | balance_cents | transfer_status
------+---------------+-----------------
 Ada  |         75000 | debited
```

## Point C — the node dies

Oban brings the job back. The module is re-read, the DAG re-derived, and every step holding a
ledger row returns its recorded value instead of running.

```
>>> provider calls: quote_payout=1  fund_vault=1  send_payout=1
>>> replaying the run as if the node had died and oban retried the job
```

```sql
select left(w.id::text, 8) as workflow,
       encode(substring(c.step_key from 1 for 6), 'hex') as step_key, c.step_label
from magma_checkpoints c join magma_workflows w on w.id = c.workflow_id order by c.id;
```
```
 workflow |   step_key   |  step_label
----------+--------------+---------------
 019fab9c | 36e87923c795 | :transfer
 019fab9c | b99960e99966 | :quote
 019fab9c | 1b00f06b7b02 | :confirmation
 019fab9c | e5489d49b284 | :debit
 32919cb1 | e25a0b993629 | :fund
 32919cb1 | f6172980f051 | :send
 019fab9c | b3b43d3af5f0 | :rail
```

```
>>> provider calls: quote_payout=1  fund_vault=1  send_payout=1
```

Identical on both sides of the replay, and the provider was called once. `step_key` is the
sha256 of the step's **name** — that is the entire identity scheme, and the reason steps can be
reordered freely between deploys.

## Point D — settled

```elixir
Magma.signal(workflow.id, "settlement", %{outcome: :completed})
```

```sql
select left(id::text, 8) as id, split_part(module, '.', 3) as module, status
from magma_workflows order by id;
```
```
    id    |  module   |  status
----------+-----------+-----------
 019fab9c | Workflows | completed
 32919cb1 | Rails     | completed
```

```sql
select left(w.id::text, 8) as workflow, c.step_label
from magma_checkpoints c join magma_workflows w on w.id = c.workflow_id order by c.id;
```
```
 workflow |  step_label
----------+---------------
 019fab9c | :transfer
 019fab9c | :quote
 019fab9c | :confirmation
 019fab9c | :debit
 32919cb1 | :fund
 32919cb1 | :send
 019fab9c | :rail
 019fab9c | :settlement
 019fab9c | :settle
```

The spine's rows read top to bottom are the payout's life story. `Magma.Testing.tape/1` returns
exactly that, and asserting on it pins a workflow's shape.

```sql
select c.name, c.balance_cents, t.status as transfer_status
from customers c join transfers t on t.customer_id = c.id;
```
```
 name | balance_cents | transfer_status
------+---------------+-----------------
 Bea  |         75000 | completed
```

A stray job arriving for an ended workflow declines to do anything:

```
{:cancel, "workflow 019fab9c-50f4-7cab-abce-da048398cf62 already ended as completed"}
```

## Point E — rejected, and unwound

Back to Ada. `Steps.Settle` answers `{:error, %Payouts.Rejected{}}`.

Rollback runs on the same idea, in reverse. The ledger is walked newest-first, each step's
`undo/4` is called with the value it recorded, and the row is **marked** rather than deleted.

```sql
select left(id::text, 8) as id, split_part(module, '.', 3) as module, status
from magma_workflows order by id;
```
```
    id    |  module   |  status
----------+-----------+-----------
 019fab9b | Workflows | failed
 247d5158 | Rails     | completed
```

```sql
select left(w.id::text, 8) as workflow, c.step_label, c.undone_at is not null as undone
from magma_checkpoints c join magma_workflows w on w.id = c.workflow_id order by c.id;
```
```
 workflow |  step_label   | undone
----------+---------------+--------
 019fab9b | :transfer     | f
 019fab9b | :quote        | f
 019fab9b | :confirmation | f
 019fab9b | :debit        | t
 247d5158 | :fund         | f
 247d5158 | :send         | f
 019fab9b | :rail         | f
 019fab9b | :settlement   | f
```

```sql
select name, kind, deadline from magma_waiters;
```
```
 name | kind | deadline
------+------+----------
(0 rows)
```

```sql
select c.name, c.balance_cents, t.status as transfer_status
from customers c join transfers t on t.customer_id = c.id;
```
```
 name | balance_cents | transfer_status
------+---------------+-----------------
 Ada  |        100000 | debited
```

The money is back. The `undone` column is the mechanism:

- **The marks are the rollback's own progress log.** A crash halfway through a rollback resumes
  from whatever is still standing. Rollback is as durable as the forward run, for the same
  reason.
- **Only `:debit` came back** — only `Steps.Debit` implements `undo/4`. A step with no undo
  keeps its row: its effect is out there in the world, and the ledger says so.
- **The first mark is a one-way door.** The workflow moves to `unwinding` and never runs
  forward again.

## Gotchas

**A step's name is its key.** Renaming a step re-runs it on the next attempt. Reordering costs
nothing; renaming is a data migration.

**Determinism is automatic for data, not for decisions.** Arguments are rebuilt from the ledger
and the workflow inputs, so they cannot drift. Control flow can. A `where` that passed is
pinned — magma rewrites user guards so a step with a checkpoint forces `:cont`. But a guard
that *skipped* records nothing, so a condition that flips false → true runs the step on the
second attempt. `switch` predicates and `map` sources are re-evaluated fresh every attempt for
the same reason: their parent step holds no checkpoint. **Derive every branch decision from
`input()`/`result()`, or make it inside a step and return it as that step's output.**

**Undo must reverse everything the step did.** Look at Point E again: the balance came back but
`transfer_status` is still `debited`, because `Debit.undo/4` restores the balance and destroys
the ledger entry and nothing else. Magma will not notice.

**An error unwinds; only a crash retries.** An `{:error, ...}` surviving Reactor's own retries
ends the run and rolls it back. A raise or a node death is Oban's problem and comes back as
another attempt. Choose deliberately which one a step returns.

**Outputs must survive `term_to_binary`.** Checkpoints are Erlang terms in a `bytea`. No pids,
no functions, no live structs.

**A `map` source must be stably ordered.** Generated step names carry the index, so a source
that reorders replays the wrong checkpoint into an element.

**Composites are one checkpoint.** `group`, `around`, `recurse` and `compose` run a private
reactor, so each is a single step with a single row and its children re-run together. Reach for
`Magma.Step.Dispatch` and a child workflow when children need their own checkpoints.

**Actor and tenant are snapshots.** Stored on the workflow row at start and replayed as they
were. A permission revoked mid-flight is not seen by the run.

## Testing

```elixir
use Magma.Testing, repo: MyApp.Repo

test "a payout waits for the customer to confirm the quote before touching their balance" do
  customer = a_customer(100_000)
  transfer = a_transfer(customer, 25_000)

  workflow = start_payout(transfer)

  assert status(workflow) == :waiting
  assert balance(customer) == 100_000
  assert transfer_status(transfer) == :requested
end
```

| Helper | |
|---|---|
| `run_workflows/1` | drains a queue, including jobs started while draining |
| `tape/1` | standing checkpoints in completion order |
| `recorded/2` | what a named step recorded |
| `status/1` | what the store last wrote |

To test recovery, call the worker again by hand — that is exactly what Oban does after a node
dies:

```elixir
Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

assert Provider.calls(:send_payout) == 1
```

## Further

- [`README.md`](../README.md) — the shape of the library
- [`DECISIONS.md`](../DECISIONS.md) — what shaped magma, and what each choice rules out
- [`examples/payouts`](../examples/payouts) — the app every output above came from
