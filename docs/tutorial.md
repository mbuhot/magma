# Magma, in one sitting

Durable workflows: what they are, how to write one, and what one looks like from the inside.
The `iex` transcripts are one unbroken session against `examples/payouts`.

## The problem

Paying a customer out of a neo bank is a multi-step process across systems you do not control,
and it can take two days to reach settlement. Price the transfer with a provider. Show the
customer that price and wait for them to accept it. Debit their balance. Hand the money to a
payment network. Wait for the far end to confirm it landed — or to bounce it back.

Four words from that world are used throughout:

| Term | Meaning |
|---|---|
| **offramp** | the exit from your system to the ordinary banking world — a customer's balance leaves and lands in a bank account |
| **quote** | the price of that exit, fixed for a short window: exchange rate, fee, and what arrives at the far end |
| **rail** | the payment network that actually moves the money. Different currencies are served by different providers, each with its own steps |
| **settlement** | the far end confirming, hours or days later, that the money arrived — or that it bounced |

Some of those steps take milliseconds. Some take a day and arrive as a webhook. Between any two
of them the process running your code can be deployed over, killed by the scheduler, or lost
with its node.

The work already done is real. Money left an account. A provider has a transfer on its books.
When the code comes back it has to answer:

| Question | Answered by hand |
|---|---|
| Was this customer already debited? | read your own tables and infer |
| Was the price they accepted the price we charged? | re-quote and hope it hasn't moved |
| Does the provider already have this transfer? | call them and reconcile |
| The far end rejected it — who gives the money back? | a script someone writes later |

Each answer is a state machine, a status column and a reconciliation job, all of which have to
stay correct as the process grows a step. The logic of the payout ends up spread across them.

## Durable workflows

A **durable workflow** is that same process written once, as a sequence, that survives the
death of whatever is running it.

```elixir
transfer = load(transfer_id)
quote = price(transfer)
approval = wait_for_the_customer(quote)   # this may take fifteen minutes
debit(transfer, approval)
outcome = wait_for_settlement(rail)       # this may take two days
settle(transfer, outcome)
```

The shape of the code is the shape of the process. Two things about it would be reckless
without an engine underneath: it blocks for two days, and if it dies partway it has no idea
where it was.

An engine fixes both. It records each step as it completes, so a process that comes back knows
what is already true, and it holds the waiting so no process has to. You write a sequence. What
runs is a series of short attempts against a persistent record.

Magma is inspired by [DBOS](https://www.dbos.dev); Temporal and Restate are the same family. It
builds the model out of pieces an Elixir application probably already has.

## The model, in two pieces

A workflow is **a recipe and a ledger.**

The **recipe** is your workflow module. It is code, and it is re-read from source on every
attempt. Nothing about the run is serialised — no continuation, no program counter, no
half-built graph.

The **ledger** is one row per step, holding what that step returned. A row appears the moment a
step succeeds, before the next step starts.

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

Three consequences.

**Nothing is ever done twice.** The customer is debited once because the second attempt finds
`:debit` in the ledger and skips it.

**Waiting is free.** A workflow parked at `await` holds no process, no job and no memory — it
is a row and a scheduled wakeup. A forty-eight hour wait costs nothing.

**A crash is not special.** Losing the node is the same event as any other attempt boundary.
There is no recovery path to write, because recovery *is* the normal path.

In exchange, a step must do one thing and return a value describing what it did. What the
ledger cannot capture, replay cannot protect.

## The four parts

| | Supplies |
|---|---|
| **Reactor** | the recipe — a DAG, concurrency, compensation and undo |
| **Oban** | the durable execution slot, retry backoff, scheduling |
| **Ash** | the ledger, as resources your application owns |
| **Magma** | the decoration that ties them together |

Magma has no engine of its own. It rewrites the reactor your DSL describes, wrapping each
step, rewriting its guards and adding middleware, then calls `Reactor.run/4` inside an Oban job.
The planner, the executor loop and the concurrency are untouched. A plain `use Reactor` module
runs durably as it stands.

Installing it:

```elixir
def deps, do: [{:magma, github: "mbuhot/magma"}]
```

```sh
mix igniter.install magma
mix ecto.migrate
```

That writes four resources into a domain of your own and points magma at them.

| Resource | Holds |
|---|---|
| workflow | one row per run: module, inputs, actor, status, result |
| checkpoint | the ledger — one row per completed step |
| signal | events delivered from outside, consumed once |
| waiter | what a parked workflow waits for, and until when |

They are ordinary source files in your own domain. Add a policy or an attribute whenever you
need one.

Checkpoint outputs are Erlang terms. A step's recorded value comes back out of the database as
the map or struct it went in as, so everything below is `iex` rather than `psql`.

## The workflow

The process from the top of this page, written for real.

```elixir
defmodule Payouts.Offramp.Payout do
  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  magma do
    queue :payouts
  end

  input :transfer_id

  read_one :transfer, Payouts.Offramp.Transfer, :by_id do
    inputs %{id: input(:transfer_id)}
    load value([:customer])
    fail_on_not_found? true
  end

  step :beneficiary, Steps.Beneficiary do
    argument :transfer, result(:transfer)
  end

  step :quote, Steps.Quote do
    argument :transfer, result(:transfer)
    wait_for :beneficiary
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

  dispatch :rail do
    workflow &Payouts.Routing.rail_for/2
    inputs &Payouts.Offramp.Payout.rail_inputs/2
    queue :rails
    argument :transfer, result(:transfer)
    argument :quote, result(:quote)
    argument :beneficiary, result(:beneficiary)
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

Top to bottom: load the transfer, check we have an account the rail will pay, price it, wait
for the customer to accept that price, take the money, hand it to whichever rail serves the
currency, wait for the far end, record how it ended.

| Step | Does |
|---|---|
| `:transfer` | reads the payout request and the customer who asked for it |
| `:beneficiary` | finds the destination account the rail has already accepted, and fails the run if there is none |
| `:quote` | asks the provider what this costs and what arrives |
| `:confirmation` | parks until the customer accepts the quote, or fifteen minutes pass |
| `:debit` | posts the debit to the ledger and moves the transfer to `:debited`. **The only step with an `undo/4`** |
| `:rail` | starts the provider's own workflow as a durable child and waits for it |
| `:settlement` | parks until the far end reports, for up to a day |
| `:settle` | marks the transfer completed, or fails the run on a rejection |

Three of the eight are magma entities; everything else is ordinary Reactor and Ash.Reactor.

| Entity | |
|---|---|
| `await` | parks until a named signal arrives. `Magma.signal/3` delivers one — from a webhook handler, a controller action, a child workflow finishing |
| `poll` | checks a condition on an interval, for a far end that will never call you. Unused here |
| `dispatch` | starts another workflow as a durable child and waits for its result |

A `timeout` is a deadline on the wait, not on the work. Reaching it fails the run by default.
That is how the quote's expiry is enforced: `:confirmation` cannot succeed once the price it
holds has gone stale. `on_timeout: :return` yields `:timeout` instead, for a workflow that would
rather branch than fail.

State flows through Reactor's own templates, `input/1` and `result/1`. Magma adds no state
channel of its own. **Arguments hold no checkpoint; outputs do.** Every attempt rebuilds a
step's arguments out of the ledger and the workflow's inputs, so a replayed step is handed what
it was handed the first time.

## Watching one run

This is a dev console with Oban's queues running. Work happens in the background, and the
transcript sleeps to let it land. [Testing](#testing) shows the deterministic version.

`Payouts.Console` is the app's own API — the same functions the web console calls. Everything
below goes through it.

```elixir
iex(1)> Logger.configure(level: :error)
:ok
iex(2)> alias Payouts.{Console, Offramp, Provider}
[Payouts.Console, Payouts.Offramp, Payouts.Provider]
iex(3)> alias Payouts.Offramp.Payout
Payouts.Offramp.Payout
iex(4)> tape = fn id -> Magma.steps(id) |> Enum.sort_by(& &1.id) |> Enum.map(& &1.step_label) end
#Function<42.113135111/1 in :erl_eval.expr/6>
```

`Magma.steps/1` is the ledger. Sorted by id it gives the **tape**: the steps a workflow has
recorded, in the order they finished.

### Starting

Ada gets an opening balance, a KYC decision from the rail, and a bank account it has agreed to
pay. Onboarding and registration are two more durable workflows; this walkthrough is about the
third.

```elixir
iex(5)> {:ok, ada} = Console.fund("Ada", 100_000)
iex(6)> balance = fn -> {:ok, c} = Offramp.get_customer(ada.id); c.balance_cents end
iex(7)> Console.onboard(ada.id, "EUR"); Console.register(ada.id, "EUR"); Process.sleep(12000)
:ok
iex(8)> {:ok, transfer} = Console.request(ada.id, "EUR", 25_000)
{:ok,
 %Payouts.Offramp.Transfer{
   id: "019fac09-be0a-773f-b394-d028710f0439",
   source_amount_cents: 25000,
   destination_currency: "EUR",
   status: :requested,
   ...
 }}
```

`Console.request/3` records the transfer and starts the payout. It hands back the transfer and
nothing else — no workflow id to store, because the id is derived from the transfer:

```elixir
iex(9)> workflow_id = Payout.workflow_id(transfer.id)
"6ea34f92-cc30-7b31-9bf8-385f36a8b358"
```

Anything holding a transfer can find its payout. Asking twice starts one workflow.

### Parked

```elixir
iex(10)> Process.sleep(12000)
:ok
iex(11)> {:ok, w} = Magma.fetch(workflow_id); {w.status, w.error}
{:waiting, nil}
iex(12)> tape.(workflow_id)
["{:__input__, :transfer, [:id]}", ":transfer", ":beneficiary", ":quote"]
```

Three steps ran, then the workflow reached `await :confirmation` and stopped. The first entry
is not one you wrote: `read_one` is an Ash.Reactor entity that expands into several Reactor
steps, and each of them checkpoints like any other.

The ledger holds real terms, not blobs:

```elixir
iex(13)> Magma.steps(workflow_id)
...(13)> |> Enum.find(&(&1.step_label == ":quote"))
...(13)> |> Map.fetch!(:output)
%{destination_amount: 69500, quoted_at: 278, rate: 278}
```

That map is the price Ada is shown. No later attempt can re-price this payout, because no later
attempt will run `:quote`.

The jobs behind it:

```elixir
iex(14)> Payouts.Repo.all(Oban.Job)
...(14)> |> Enum.filter(&(&1.queue == "payouts"))
...(14)> |> Enum.map(&{&1.id, &1.state, &1.scheduled_at})
[
  {4, "scheduled", ~U[2026-07-29 04:17:27.522697Z]},
  {3, "completed", ~U[2026-07-29 04:02:27.480167Z]}
]
```

Job 3 is **completed**. Nothing is executing and nothing is held in memory. All that exists is a
row and job 4, scheduled at the fifteen-minute timeout.

```elixir
iex(15)> balance.()
100000
```

Her money has not moved. The quote was taken and nothing was charged.

### Confirming

```elixir
iex(16)> Console.approve(workflow_id); Process.sleep(12000)
:ok
iex(17)> tape.(workflow_id)
["{:__input__, :transfer, [:id]}", ":transfer", ":beneficiary", ":quote",
 ":confirmation", ":debit", ":rail"]
```

`Console.approve/1` is `Magma.signal(workflow_id, "confirm", ...)`. The signal and the job that
wakes the workflow commit in one transaction. A crash on the sending side cannot leave a parked
workflow with nothing coming for it.

Three steps later the run is parked again, on `:settlement`. The wait itself recorded a row:
the signal's payload is `:confirmation`'s output.

```elixir
iex(18)> Magma.steps(workflow_id)
...(18)> |> Enum.find(&(&1.step_label == ":confirmation"))
...(18)> |> Map.fetch!(:output)
%{confirmed_by: "console"}
iex(19)> balance.()
75000
```

A wait that has been satisfied never waits again, and the balance has moved.

### The child

`dispatch :rail` started a second workflow, under an id derived the same way:

```elixir
iex(20)> rail = Magma.child_id(workflow_id, :rail)
"d24c2cc6-862e-76b9-a408-d43788e0350d"
iex(21)> {:ok, r} = Magma.fetch(rail); {r.module, r.status, r.parent_signal}
{Payouts.Rails.Bridge, :completed, "magma.child.:rail"}
iex(22)> tape.(rail)
[":fund", ":send"]
```

Nowhere does the payout name `Payouts.Rails.Bridge`. `Payouts.Routing.rail_for/2` resolved it from
the transfer's currency at run time. It ran on the `rails` queue with a ledger of its own,
funding a vault before sending, which the other rail does not do. The derived id keeps a replay
from starting a second child.

### Replaying

`Console.resume/1` puts the workflow back on its queue, which is what recovery does after a
crash.

```elixir
iex(23)> {Provider.calls(:quote_payout), Provider.calls(:fund_vault), Provider.calls(:send_payout)}
{1, 1, 1}
iex(24)> Console.resume(workflow_id); Process.sleep(12000)
:ok
iex(25)> {Provider.calls(:quote_payout), Provider.calls(:fund_vault), Provider.calls(:send_payout)}
{1, 1, 1}
iex(26)> tape.(workflow_id)
["{:__input__, :transfer, [:id]}", ":transfer", ":beneficiary", ":quote",
 ":confirmation", ":debit", ":rail"]
iex(27)> balance.()
75000
```

The whole workflow ran again: module re-read, DAG re-derived, every step visited. The provider
was called once, the balance moved once, the tape is unchanged. Every step found its row and
handed back what it recorded.

### Rejection, and rollback

The far end bounces the payment.

```elixir
iex(28)> Console.settle(workflow_id, :rejected); Process.sleep(12000)
:ok
iex(29)> {:ok, w} = Magma.fetch(workflow_id); w.status
:failed
```

`Steps.Settle` answered `{:error, %Payouts.Rejected{}}`. That ends the run and rolls it back.
Rollback is the same idea in reverse: walk the ledger newest-first, call each step's `undo/4`
with the value it recorded, and **mark** the row rather than delete it.

```elixir
iex(30)> tape.(workflow_id)
["{:__input__, :transfer, [:id]}", ":transfer", ":beneficiary", ":quote",
 ":confirmation", ":rail", ":settlement"]
iex(31)> balance.()
100000
```

`:debit` is gone from the tape and Ada has her money back. Everything else still stands,
deliberately.

- **The marks are the rollback's progress log.** A crash halfway through resumes from whatever
  is still standing, so rollback is as durable as the forward run.
- **Only `:debit` came back** — only `Steps.Debit` implements `undo/4`. A step with no undo
  keeps its row: its effect is out there in the world, and the ledger says so.
- **The first mark is a one-way door.** The workflow moves to `unwinding` and never runs
  forward again.

`Magma.cancel/1` drives the same machinery on purpose. It stops a workflow wherever it is,
including one parked on a wait, and compensates for everything it has done.

The transfer did not go back to where it started:

```elixir
iex(32)> {:ok, t} = Offramp.get_transfer(transfer.id); t.status
:reversed
```

Which is the point worth the most.

### Undo leaves the world consistent, not restored

The instinct is that `undo/4` rewinds: put everything back the way it was, as though the payout
never happened. That instinct is wrong twice over.

It is usually **impossible**. A ledger entry sent to an accounting service, a transfer accepted
by a partner bank, an email that went out — none of them can be unsent. You do not own most of
what a workflow touches.

It is also usually **a lie**. Something *was* attempted. Erasing the evidence leaves a system
that cannot explain itself: a customer asking why their balance moved and came back, a
reconciliation that finds a gap, an auditor with no answer.

Undo runs because the run failed, and its job is to leave the world in a state that is **true**.
Concretely, three moves:

| | `Debit` does |
|---|---|
| Post the compensation | a `"payout reversal"` entry for `+25,000`, so the journal nets to zero and both movements are on the record |
| Move to a terminal status that says what happened | the transfer becomes `:reversed`, not `:requested` |
| Leave alone what is still true | the quote, the confirmation and the rail attempt all happened, and their checkpoints stand |

```elixir
def undo(entry, %{transfer: transfer}, _context, _options) do
  with {:ok, _reversal} <- post(transfer, -entry.amount_cents, "payout reversal"),
       {:ok, _transfer} <- set_status(transfer, :reversed) do
    :ok
  end
end
```

```elixir
iex(33)> {:ok, entries} = Offramp.ledger_entries()
...(33)> Enum.map(entries, &{&1.reason, &1.amount_cents})
[{"opening balance", 100000}, {"payout", -25000}, {"payout reversal", 25000}]
```

Three entries, netting to Ada's original balance, and the history says what happened. Note where
the reversal's amount comes from: `entry.amount_cents`, the value this step recorded, rather
than `transfer.source_amount_cents`. The compensation is for what was actually posted.

The balance follows from that automatically, because it is a `sum` aggregate over these entries
rather than a column anything writes. There is no second place for the reversal to be applied,
and no way for the two to disagree.

`:reversed` rather than `:rejected` for the same reason. `undo/4` does not know *why* it is
unwinding — `Magma.cancel/1` reaches this identical code — so it asserts only what it did. Why
the run ended is on the workflow row: `status: :failed`, carrying the `%Payouts.Rejected{}`.

This is also why a step with no `undo/4` keeps its checkpoint. Its effect is still out in the
world, and the record saying so is more useful than a clean-looking tape that lies.

## Gotchas

**Undo owns everything the step touched.** `Debit.run` posts a ledger entry and sets the
transfer's status, so `Debit.undo/4` answers for both. Magma cannot check this for you: a step
that undoes one of its two effects leaves the other standing, silently. The fewer effects a step
has, the less its compensation can get wrong — which is the practical argument for deriving
state (the balance aggregate) over storing it.

**A step's arguments are snapshots, so never compare against them.** Arguments come from the
ledger, and they hold what was true when the step upstream recorded them. `Debit.undo/4`
receives a `transfer` whose in-memory `status` still reads `:requested`, because that is what it
read when `:transfer` was checkpointed — even though the database says `:debited`. Building an
Ash changeset from that stale struct produced no changes, so the update was skipped and the
status never came back. Reload before you write:

```elixir
defp set_status(transfer, status) do
  {:ok, current} = Offramp.get_transfer(transfer.id)

  current
  |> Ash.Changeset.for_update(:set_status, %{status: status})
  |> Ash.update()
end
```

The same trap catches any read-modify-write on an argument. Treat arguments as identifiers and
intentions, and read current state from the database.

**A step's name is its key.** `step_key` is the sha256 of the step's name, so renaming a step
re-runs it on the next attempt. Reordering costs nothing, since the graph is the order. Renaming
is a data migration.

**Determinism is automatic for data, not for decisions.** Arguments are rebuilt from the
ledger, so they cannot drift. Control flow can. A `where` that passed is pinned: magma rewrites
user guards so a step holding a checkpoint forces `:cont`. A guard that *skipped* records
nothing, so a condition flipping false → true runs the step on the second attempt. `switch`
predicates and `map` sources are re-evaluated on every attempt, because their parent step holds
no checkpoint. **Derive every branch decision from `input()`/`result()`, or make it inside a
step and return it as that step's output.**

**An error unwinds; only a crash retries.** An `{:error, ...}` surviving Reactor's own retries
ends the run and rolls it back, as `:settle` did. A raise or a node death belongs to Oban and
comes back as another attempt. Choose which one a step returns.

**Outputs must survive `term_to_binary`.** No pids, no functions, no live structs.

**A `map` source must be stably ordered.** Generated step names carry the index, so a source
that reorders replays the wrong checkpoint into an element.

**Composites are one checkpoint.** `group`, `around`, `recurse` and `compose` run a private
reactor inline. Each is a single step with a single row, and its children re-run together. Use
`dispatch` when children need their own checkpoints, their own queue, or contain a wait.

**Actor and tenant are snapshots.** They are stored on the workflow row at start and replayed
as they were. A permission revoked mid-flight is not seen by the run.

## Testing

In a test the queues drain on demand instead of in the background.

```elixir
use Magma.Testing, repo: MyApp.Repo

test "a payout waits for the customer to confirm the quote before touching their balance" do
  customer = a_customer(100_000)
  transfer = a_transfer(customer, 25_000)

  {:ok, workflow} = Magma.start(Payout, %{transfer_id: transfer.id}, queue: :payouts)
  run_workflows(queue: :payouts)

  assert status(workflow) == :waiting
  assert balance(customer) == 100_000
end
```

| Helper | |
|---|---|
| `run_workflows/1` | drains a queue, including jobs started while draining |
| `tape/1` | standing checkpoints in completion order |
| `recorded/2` | what a named step recorded |
| `status/1` | what the store last wrote |

`tape/1` pins a workflow's shape, so an edit that adds, drops or reorders a step says so. For
recovery, call the worker again by hand:

```elixir
Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

assert Provider.calls(:send_payout) == 1
```

## Further

- [`README.md`](../README.md) — the shape of the library
- [`DECISIONS.md`](../DECISIONS.md) — what shaped magma, and what each choice rules out
- [`examples/payouts`](../examples/payouts) — the app this session ran against
