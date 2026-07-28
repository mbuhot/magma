# Magma

Durable workflows for Ash. A Reactor runs inside an Oban job, every step checkpoints its
output, and each later attempt replays what finished and carries on from the edge.

## The idea

Four parts, each doing what it already does well:

| | Supplies |
|---|---|
| **Reactor** | the DAG, the concurrency, compensation and undo |
| **Oban** | the durable execution slot, retry backoff, scheduling |
| **Ash** | the store, owned by your application |
| **Magma** | the decoration that ties them together |

## Getting started

```elixir
def deps do
  [{:magma, github: "mbuhot/magma"}]
end
```

```sh
mix igniter.install magma
mix ecto.migrate
```

That writes four resources into a domain of your own — `YourApp.Magma` unless `--domain`
names another — and points magma at them. They are ordinary source files, so adding a policy
or an attribute later is an edit.

## A workflow

An ordinary Reactor. Every existing entity keeps its meaning, and a plain `use Reactor`
module runs durably as it stands.

```elixir
defmodule MyApp.Checkout do
  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  magma do
    queue :payments
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

  return :charge_card
end
```

```elixir
{:ok, workflow} = Magma.start(MyApp.Checkout, %{order_id: id}, actor: current_user)

Magma.signal(workflow.id, "confirm", %{approver: "sam"})
```

State flows through Reactor's own argument templates — `input/1`, `result/1`, `result/2`.
Magma adds no state channel, and that is what makes replay work: **arguments hold no
checkpoint, outputs do.** Each attempt rebuilds a step's arguments from the outputs upstream
and the workflow's inputs, so they match by construction.

## How it works

**Replay keys on step names.** A step's identity is its declared name, hashed with a
deterministic encoding. Checkpoints commit in whatever order the work finishes, parallel
branches checkpoint independently, and the DAG is re-derived from the DSL every attempt.
Reordering steps costs nothing, because the graph is the order.

**Interception happens before the run.** Magma rewrites the built `%Reactor{}` — wrapping
each step's impl, rewriting its guards, adding middleware — then calls `Reactor.run/4`. The
planner and executor loop are untouched. Checkpoints load once per attempt into the context,
so a step's lookup is a map read.

**Waiting releases the job.** `await` takes a signal already delivered straight
away, blocks briefly for one that may be seconds off, then halts. The workflow becomes a row
holding no process and no job. `Magma.signal/3` writes the signal and the resume job in one
transaction, so a wakeup survives a crash on the sending side.

`poll` covers the other case — nothing will push you, so the job snoozes and comes
back on its own.

**A crash retries, an error unwinds.** Node death is invisible to Reactor and belongs to
Oban. An `{:error, ...}` that survives Reactor's own retries ends the run and rolls it back.

**A rollback that starts, finishes.** The first checkpoint taken back moves the workflow to
`unwinding`, and from there it never runs forward again. `Magma.Unwind` walks the standing
checkpoints newest-first and drives each step's `undo/4`. The marks are the progress log, so
a crash mid-rollback carries on from exactly where it stopped.

## Testing

```elixir
use Magma.Testing, repo: MyApp.Repo

test "a payout survives its worker dying" do
  {:ok, workflow} = Magma.start(MyApp.Payout, %{transfer_id: id})

  run_workflows()

  assert tape(workflow) == [":quote", ":debit", ":transfer"]
  assert status(workflow) == :completed
end
```

`tape/1` is the checkpoint sequence in completion order. Asserting on it pins a workflow's
shape, so an edit that adds, drops or reorders a step says so.

## What to know before writing one

- Step names are the checkpoint keys, so renaming a step re-runs it.
- Step outputs must survive a `term_to_binary` round trip.
- A `map` source must be stably ordered, since generated names carry the index.
- `group`, `around`, `recurse` and `compose` run a private reactor, so each is one step with
  one checkpoint and its children re-run together.
- `compose` records a live `%Reactor{}` when it supports undo, so that step is left
  uncheckpointed and its nested reactor re-runs.

## Retention

Nothing is deleted by default. A workflow can say how long its rows are kept once it ends,
and `config :magma, retention: ...` is the fallback:

```elixir
magma do
  retention :timer.hours(24 * 7)
end
```

`Magma.Pruner` runs the deletion from Oban's cron.

## Reading further

- [`DECISIONS.md`](DECISIONS.md) — what shaped magma, and what each choice rules out
- [`docs/superpowers/specs/`](docs/superpowers/specs/) — the full design

## Development

Needs Elixir ~> 1.18 and Postgres on `localhost:5432` (`postgres`/`postgres`).

```sh
mix setup
mix test
```

## Credit

The durable-execution model — checkpoint each step, replay on recovery — comes from
[DBOS](https://www.dbos.dev). Magma reaches it by composing Reactor, Oban and Ash.

## License

MIT.
