# Magma

Durable workflows for Ash. A Reactor runs inside an Oban job, every step checkpoints its
output, and each later attempt replays what finished and carries on from the edge.

> **Status: under construction.** The design is settled and recorded; the code is being
> built against it. Nothing here is usable yet.

## The idea

Four parts, each doing what it already does well:

| | Supplies |
|---|---|
| **Reactor** | the DAG, the concurrency, compensation and undo |
| **Oban** | the durable execution slot, retry backoff, scheduling |
| **Ash** | the store, owned by your application |
| **Magma** | the decoration that ties them together |

A workflow is an ordinary Reactor with three entities added — a `magma` section, `await`
and `poll`. Every existing entity keeps its meaning, and a plain `use Reactor` module runs
under magma as it stands.

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

## How it works

**Replay keys on step names.** A step's identity is its declared name, hashed. Checkpoints
commit in whatever order the work finishes, parallel branches checkpoint independently, and
the DAG is re-derived from the DSL on every attempt. Reordering steps costs nothing, because
the graph is the order.

**Interception happens before the run.** Magma rewrites the built `%Reactor{}` — wrapping
each step's impl, rewriting its guards, adding middleware — then hands it to `Reactor.run/4`.
The executor loop is left alone.

**Waiting releases the job.** An `await` blocks briefly for a signal that may be seconds
away, then halts. The workflow becomes a row and the Oban job completes. A signal write and
its resume-job insert share one transaction, so a wakeup survives a crash on the sending
side.

**A crash retries, an error unwinds.** Node death is invisible to Reactor and belongs to
Oban. An `{:error, ...}` that survives Reactor's own retries is you declaring the run over,
and it rolls back.

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
[DBOS](https://www.dbos.dev). Magma reaches it by composing Reactor, Oban and Ash instead of
running an engine of its own.

## License

MIT.
