# Magma Usage Rules

Magma makes a Reactor workflow durable: every checkpointed step's result survives a crash, and
a wait can park the whole run without holding a process or a job. It adds three entities —
`await`, `poll`, `dispatch` — and decorates every step Reactor already has.

## Where a wait may live

`await`, `poll` and `dispatch` are ordinary Reactor steps. They work in:

- a reactor's top-level body
- a `switch` branch
- a `map` element

They raise, naming the step and the composite it sits inside, in `group`, `around`, `recurse`
and `compose` — a nesting composite runs its children in a private reactor magma never sees, so
a halt in there cannot be read back. Move the wait into the outer reactor, or under a `map` or
a `switch`.

```elixir
recurse :loop, MyApp.LoopBody do
  dispatch :leg do
    workflow(MyApp.Leg)
    argument(:transfer_id, input(:transfer_id))
  end
end
```

```
dispatch :leg sits inside :loop, a nesting composite that runs its steps in a private reactor.

Such a step holds no checkpoint of its own and cannot halt to wait. Move it into the
outer reactor, or under a `map` or a `switch`.
```

## Choosing a boundary

| Shape | Use it for |
|---|---|
| Flat reactor body | The default. Steps in sequence, each its own checkpoint. |
| `switch` | A step, wait, or child that only exists down one branch. |
| `map` | The same steps, repeated once per element of a collection, each element's own checkpoint. |
| `dispatch` | A step that needs a wait of its own, its own queue, its own retries, or that another workflow also needs to run. |
| `group` / `around` / `recurse` / `compose` | An atomic unit whose retry re-runs every step inside it. Holds no wait. |

Default to a flat body. Reach for `map` when the work repeats over a collection, `dispatch`
when a step needs to be a workflow in its own right, and a nesting composite only when re-running
the whole unit on retry is what's wanted.

## Checkpoint granularity

- A checkpointed step runs **at most once**: a replay reads its recorded value back.
- A nesting composite (`group`, `around`, `recurse`, `compose`) records once, for itself, not
  for its children — its children hold no checkpoint of their own and **re-run together** if
  the run comes back before the composite recorded.

A non-idempotent effect inside a nesting composite needs its own checkpoint: pull it out to a
plain step in the outer reactor, or under a `map`/`switch`.

## Alternative outcomes

Sibling waits that depend on nothing all park on the same attempt, and a signal reaches its
workflow whatever it is presently parked on, so independent waits are answered in whatever order
they are told in.

Two sibling `await`s on different signal names cannot both be answered — only one of the
mutually exclusive events actually happens, so the other sits parked forever and the reactor
never finishes. Model the choice as one wait whose outcome discriminates:

- one `poll` whose returned status discriminates
- one `await` whose signal payload discriminates, read with a `switch`
- one `await` with `on_timeout: :return`, discriminated against the `:timeout` value

```elixir
await :settlement do
  signal("settlement.completed")
  timeout(:timer.hours(72))
end

switch :outcome do
  on(result(:settlement))

  matches?(&(&1.status == :settled)) do
    step(:release, Steps.Release)
  end

  default do
    step(:refund, Steps.Refund)
  end
end
```

## A dispatched child's failure

`dispatch` surfaces a child's error as the dispatching step's own failure, so it unwinds the
caller exactly as any other step's error does. An expected failure is a return value the
child's workflow completes with:

```elixir
%{outcome: :condition_failed, kind: :finance}
```

The dispatching step gets that map back as its result and branches on it. A `dispatch` that
raises indicates a bug in the child.

## What a failed child hands back

A child that failed reaches the caller as a `Magma.ChildError`:

```elixir
%Magma.ChildError{
  workflow_id: "019faae3-...",
  module: MyApp.Rail,
  error: %RuntimeError{message: "the rail is down"}
}
```

`workflow_id` and `module` name the child. `error` is the child's own error — match on it when
the caller cares what went wrong. `Exception.message/1` reads down a chain of dispatches to the
cause, so an engagement failing four levels deep names every workflow between.

A child that failed while taking its own work back hands back the same thing.

## Addressing fan-out

A signal name is fixed at compile time, so an `await` inside a `map` shares one signal name
across every element. Signals answer elements in the order they parked — the first signal
delivered lands on element 0, the next on element 1, and so on:

```elixir
map :approvals do
  source(input(:order_ids))

  await :confirmation, signal: "confirm" do
    argument(:order_id, element(:approvals))
  end
end
```

When elements must be addressed individually — a specific order confirmed out of turn, a
specific child failing on its own — use `dispatch` per element. Each element derives
its own child id, so each can be signalled, adopted, and reported on independently.

## `map` concurrency

`allow_async?` defaults to `false` on `map`. A `dispatch` inside a `map` left at the default
starts, waits for, and reports on one element before starting the next. Set `allow_async?(true)`
to start every element's child before any of them has answered:

```elixir
map :rails do
  source(input(:transfer_ids))
  allow_async?(true)

  dispatch :rail do
    workflow(MyApp.Rail)
    argument(:transfer_id, element(:rails))
  end
end
```

## Timeouts

`timeout` on `await` and `dispatch` is measured once, on the attempt that first parks the wait,
and the deadline is held on the waiter row. Every later attempt reads that same deadline back —
a resolver that would answer differently on a later attempt cannot move a deadline already set.

Accepted forms:

- an integer, in milliseconds
- a 2-arity function over the step's arguments and context
- an MFA, called with arguments and context prepended

```elixir
await :confirmation do
  signal("confirm")
  timeout(fn %{policy: policy}, _context -> policy.cooling_off_ms end)
end
```

## Loops

A wait cannot live inside `recurse` — `Reactor.Step.Recurse` reuses the same step name for
every iteration, so a `dispatch` there would derive one child id for every iteration and a
later iteration would adopt an earlier one's finished child. A `recurse` that needs a wait or
an effect per iteration expresses the loop as a chain of self-dispatching children: each
iteration's workflow dispatches the next, carrying forward whatever state the loop needs.
A `recurse` that stays pure — no wait, no checkpointed effect — is unaffected.

## Testing

`Magma.Testing.run_workflows/1` wraps `Oban.drain_queue/1` with defaults suited to draining a
whole workflow tree in one call: `queue: :default`, `with_recursion: true`,
`with_safety: false`.

To reach a wait whose deadline lies in the future, add `with_scheduled: true` and set
`with_recursion: false` in the same call:

```elixir
run_workflows(with_scheduled: true, with_recursion: false)
```

Keep those two options apart. `with_scheduled: true` treats a job scheduled for any future
time as due now, and a snoozed `poll` reschedules its own job. Held together with
`with_recursion: true`, that pair runs a poll, runs the job its snooze schedules, runs the next
one, and continues without bound. Drain with recursion for ordinary progress, and use a single
non-recursive pass to reach a scheduled wait.

A snoozed `poll` otherwise sits until its scheduled time arrives, or until something calls
`Magma.wake/1` for its workflow. A caller that has just moved the outside system a poll watches
asks for the look with `Magma.wake/1` rather than waiting out the interval.

## Where a step can run twice

One attempt holds a workflow at a time, and every other job for it waits its turn. How long an
attempt may hold it is `lease_ms`, on the workflow or in config, and it has to outlast the longest
attempt the workflow makes:

```elixir
magma do
  queue :sales
  lease_ms :timer.minutes(30)
end
```

A step abandoned by a halt is not a job and is not held by the claim, so its effect can still
happen twice — see `DECISIONS.md` §32. A step whose effect cannot be repeated carries an
idempotency key of its own.

## The entities

`Magma.Dsl.Await`, `Magma.Dsl.Poll` and `Magma.Dsl.Dispatch` document their own schemas — read
those module docs for the full option list. This document covers how the three compose with
the rest of Reactor's DSL; `DECISIONS.md` records why each constraint holds.
