# Agency — an agent's transaction coordinator, on magma

A property sells. An agent runs an agency agreement from signature to commission disbursed:
compliance documents, a marketing campaign, an attempt to sell, exchange, cooling off,
conditions, settlement. Each of those is a wait measured in days, and a contract that falls
over sends the agent straight back to work — call an underbidder, or go to market again.

## The core idea: three answers to "it depends"

A sale branches on three different things, and each is modelled with the tool that actually
fits it.

| Question | Answer | Because |
|---|---|---|
| Auction, set date, or private treaty? | a structural `switch` | fixed at the attempt's own setup, known before any child runs |
| Which state's compliance rules apply? | a `dispatch` resolved at run time | the child module is looked up from the property's jurisdiction |
| Does cooling off apply? | a small `switch` on the resolved policy | auction sales are exempt; set date and treaty sales carry a window |

The sale method decides the shape of a whole subtree. The jurisdiction decides which module a
dispatch reaches for. Cooling off turns on a policy value read back from the jurisdiction and
branched on in place.

## The workflow tree

```
Engagement                        one per agency agreement
├── <jurisdiction> Gate           dispatch, resolved from the property's jurisdiction
│                                 NSW.Gate | VIC.Gate | QLD.Gate — same shape, different documents
└── Campaign                      one marketing run; relaunches as its own child
    └── Attempt                   one generation of trying to sell
        ├── Auction               switch: sale_method == :auction
        │   └── PrivateTreaty     dispatched on "passed in"
        │       └── Negotiation   dispatched; a counter dispatches the next round
        ├── SetDateSale           switch: sale_method == :set_date
        │   └── Negotiation       one dispatched child per live offer, run concurrently
        ├── PrivateTreaty         switch: sale_method == :treaty
        │   └── Negotiation
        └── Conditions            dispatched once exchanged
```

An `Attempt` that fails waits for the agent's decision, then:

- **dispatches a successor generation** — a fresh `Attempt` against a named underbidder, or
- **dispatches a fresh `Campaign`** — relaunch, new marketing, new buyers.

Both are children of the same `Attempt`, chosen by what the agent answers.

## The two screens

| Screen | Speaks | Shows |
|---|---|---|
| **Sales desk** (`/`) | the agent's language | one listing, its stage, and the actions available right now |
| **Console** (`/console`) | the machinery | every workflow, its dispatch tree, its parked waits, its checkpoints |

Every button on the sales desk delivers a signal to the workflow behind the listing, or moves an
external system's state and lets the workflow notice.
The console reads the same rows and shows what a developer would want: module names, step keys,
signal names, queues.

## Running it

Needs Postgres on `localhost:5432` (`postgres`/`postgres`).

```sh
mix setup
mix agency.seed
mix phx.server
```

`mix setup` creates and migrates the dev database. `mix agency.seed` wipes it and rebuilds four
listings, each driven forward with real signals to a deliberately different wait:

| Listing | Sale method | Parked at |
|---|---|---|
| 14 Kurraba Road | Set date | Offers in, three buyers to work |
| 8 Rialto Street | Auction | Auction day, one bidder on record |
| 22 Ardoyne Road | Private treaty | Cooling off, an accepted offer under contract |
| 51 Marine Parade | Set date | A contract fell through — agent choosing an underbidder or relaunch |

Open `http://localhost:4000` for the sales desk, `http://localhost:4000/console` for the
machinery behind it.

## `await` versus `poll`

Both entities wait; which one fits depends on who resolves it.

| | Used for | Because |
|---|---|---|
| `await` | a signature arriving, a hammer falling, cooling-off rescission, a negotiation's response, a vendor's selection, an inspection report | a person decides, and that decision is delivered as a signal |
| `poll` | finance approval, title clearance, settlement | an external system (lender, title office, PEXA) holds queryable state, and the workflow checks in on an interval until it changes |

Conditions resolves all three at once: finance and title are polled against systems, inspection
is awaited because a buyer's inspector reporting back is a person deciding.

## Deeper docs

See the repo root [`usage-rules.md`](../../usage-rules.md) for how `await`, `poll` and
`dispatch` compose with the rest of Reactor's DSL.
