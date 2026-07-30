# Property Sale Branching Example — Implementation Plan

**Goal:** Ship `examples/agency`, a transaction-coordinator example themed on branching and
long human awaits, plus the magma fix its investigation uncovered.

**Spec:** `docs/superpowers/specs/2026-07-30-property-sale-branching-example-design.md`

**Architecture:** An `Engagement` workflow holds the gate and campaign, which survive a
contract falling over. Everything from method selection to settlement lives in a
`SaleAttempt` child, and a failed attempt dispatches its successor, carrying the buyer
register forward. Sale method is a structural `switch`; jurisdiction resolves a gate reactor
at run time; cooling-off is an inline `switch` on the resolved policy.

**Tech stack:** Elixir, Reactor, Ash, AshPostgres, Oban, Phoenix LiveView, magma.

## Global constraints

- Follow the patterns in `examples/payouts` and `examples/helpdesk`. Read both before writing.
- Statuses and closed sets are `Ash.Type.Enum` modules. No bare strings, no boolean flags.
- No inline comments. Docs at module and public-function level only, one line each.
- Tests describe behaviour from the caller's side. No conditional assertions.
- `listing_live` carries no workflow vocabulary — no step names, checkpoints, or entity names.
- Format with `mix format` immediately before each commit.

## Task groups and sequencing

| Group | Task | Depends on | Worker |
|---|---|---|---|
| **A** | `dispatch` inside `recurse` derives colliding child ids — pin and resolve | — | Opus 5, high |
| **B1** | `examples/agency` scaffold: Phoenix + Ash + magma, boots and compiles | — | Sonnet 5, high |
| **B2** | `Agency.Sale.Clock` and `Agency.Sale.Jurisdiction` with NSW/VIC/QLD | B1 | Sonnet 5, high |
| **B3** | Ash resources and enums | B1 | Sonnet 5, high |
| **C1** | Compliance gate reactors, one per jurisdiction | B2, B3 | Sonnet 5, high |
| **C2** | `Negotiation`, and the three sale-method reactors | B3 | Opus 5, high |
| **C3** | `SaleAttempt`, cooling-off switch, conditions fan-out, commission switch | C2 | Opus 5, high |
| **C4** | `Engagement` and the generation chain | C3 | Opus 5, high |
| **D1** | Simulated third parties: conveyancer, lender, titles, PEXA | B3 | Sonnet 5, high |
| **D2** | `listing_live` — the agent's sales desk | C4, D1 | Sonnet 5, high |
| **D3** | `console_live` — the workflow inspector | C4 | Sonnet 5, high |
| **D4** | Seeded listings mix task | C4, D1 | Haiku 4.5, low |
| **E** | README and final gates | everything | orchestrator |

A and B run in parallel. B2/B3 parallel after B1. C is sequential. D2/D3/D4 parallel after C4.

## Group A — the prerequisite

`Reactor.Step.Recurse` reuses `context.current_step.name` for every iteration
(`deps/reactor/lib/reactor/step/recurse.ex:129`), so `Magma.Step.Dispatch` derives the same
child id each time and a later iteration adopts an earlier finished child.

`deps/` is a dependency and stays untouched, so the resolution lives in magma. Acceptable
outcomes, in order of preference:

1. Magma derives a child id that distinguishes iterations.
2. Magma raises a clear error when a `dispatch` is nested inside a `recurse`, with the
   constraint documented in `DECISIONS.md`.

The failing test comes first either way.

The example itself uses no `recurse` — negotiation rounds are awaits inside a workflow, and
the generation chain is dispatch-of-successor — so A and B are independent.

## Magma's own usage rules

Magma depends on `usage_rules` and publishes none, so an agent consuming the library gets no
guidance while every Ash-ecosystem dependency in this repo ships some. Building the example
surfaced enough sharp edges to make this the highest-value documentation in the project.

Write `usage-rules.md` at the repo root, split into `usage-rules/` topic files if it grows.
`DECISIONS.md` records *why* each constraint exists; usage rules state what to do. Cover:

| Rule | Substance |
|---|---|
| Where a wait may live | Reactor body, `switch` branch, `map` element. Never inside `compose`, `group`, `around`, `recurse` |
| Choosing a boundary | Flat body by default; `map` across a collection; `dispatch` for a wait, own queue, own retries, reuse; composite only when atomic re-run is wanted |
| Checkpoint granularity | At most once per checkpointed step; at least once for a whole nesting composite. Non-idempotent effects need their own checkpoint |
| Alternative outcomes | One `poll` whose status discriminates, or one signal whose payload does, or a signal against `on_timeout: :return`. Two sibling awaits deadlock |
| A child's failure | Unwinds the caller. An expected failure is a return value, never an error |
| Addressing fan-out | Signal names are static, so `map` + `await` shares one name. Use `dispatch` per element when elements must be addressed |
| `map` concurrency | `allow_async?` defaults to false, so dispatched children serialise. Set it when fan-out must be concurrent |
| Timeouts | Measured once when a wait first parks and held on the waiter row. Integer, 2-arity function, or MFA |
| Testing | `run_workflows/1` with `with_scheduled: true` and `with_recursion: true` re-executes a snoozed `poll` without bound |

Also add a line to each of `Magma.Dsl.Await`, `Magma.Dsl.Poll` and `Magma.Dsl.Dispatch` — the
entity docs are what a developer reads first, and they currently say none of this.

## Acceptance

- `mix test` green in the magma root and in `examples/agency`.
- Every spec test in the spec's test list has a corresponding test.
- A seeded listing can be played from each of the three sale methods through to commission,
  and a rescission opens a second attempt against the surviving register.
