# Property Sale — a branching example

## Why

The existing examples each carry one theme.

| Example | Theme |
|---|---|
| `payouts` | Money movement, compensation, rails |
| `helpdesk` | Identity, actor, tenant, derived authority |
| `agency` | **Branching and long human awaits** |

Neither existing example uses `switch`. This one is built around it, and around which
construct answers "it depends" in each situation.

A clickable prototype of the product view established the shape:
`https://claude.ai/code/artifact/a4585d53-66cc-40ce-b9e9-a14badd8538a`

## Domain

A real estate agent's engagement, from the signing of an agency agreement through to
commission disbursed. No single production system spans this: the agent's CRM stops at
contract, conveyancing software starts there, the lender and PEXA sit outside both. The
example app is the transaction coordinator across all of them.

Jurisdictions are NSW, VIC and QLD.

## Prerequisite: `recurse`

This work opens with a magma fix, because the example's shape depends on the outcome.

`Reactor.Step.Recurse` reuses `context.current_step.name` for every iteration
(`recurse.ex:129`). Two consequences follow.

| Consequence | Detail |
|---|---|
| One checkpoint per loop | Intermediate iterations return steps, and a step that returns steps records nothing. A six-round loop that crashes at round five replays all six. |
| Child id collision | `Magma.Step.Dispatch` derives the child id from parent id and step name. Every iteration derives the same id, so a later iteration adopts an earlier iteration's finished child and parks awaiting a signal already sent. |

`test/magma/nesting_composite_test.exs` documents the first as intended. The second is a
defect.

**Order of work.**

1. A failing test pinning `dispatch` inside `recurse`: two iterations, two distinct children.
2. A fix. Two candidate locations, chosen once the test shows the behaviour:
   - Reactor names each iteration distinctly, which fixes checkpointing at the same time.
   - Magma folds `current_iteration` into the derived id, which is contained but leaves the
     replay characteristic as it stands.
3. The example, designed against whatever holds after the fix.

`switch` needs no such work. `test/magma/composite_test.exs:42` already pins that a switch
takes the same branch on a later attempt.

## Three answers to "it depends"

The example's argument is that these are different problems.

| Decision | Construct | Why |
|---|---|---|
| Sale method | `switch` with composed branches | Few branches, each a structurally different flow |
| Jurisdiction | Runtime-resolved `dispatch` | Many branches, uniform shape, grows per state |
| Cooling-off | Small inline `switch` | Two outcomes, decided by resolved policy |

## Workflow shape

```
Agency.Sale.Engagement                     ← one per agency agreement
  agency agreement accepted
  dispatch :compliance_gate                ← module resolved from jurisdiction
  step   :launch_campaign
  await  :campaign_outcome                 ← escapes: withdrawn / term expired
  dispatch :sale_attempt                   ← the generation chain, below
  return
```

Everything from method selection to settlement lives inside a sale attempt. The gate and
the campaign sit above it, because they survive a contract falling over.

```
Agency.Sale.SaleAttempt                    ← one generation
  ▸ switch on sale_method
      auction    → compose Agency.Sale.Auction
      set_date   → compose Agency.Sale.SetDateSale
      treaty     → compose Agency.Sale.PrivateTreaty
  ← branches rejoin, each returning an exchanged contract
  ▸ switch on cooling_off policy
      applies    → await :cooling_off_expiry, timeout from policy
      exempt     → pass through            (auction lands here)
  dispatch :conditions
  await  :settlement
  ▸ switch on commission_trigger
      on_unconditional → disburse against the accrual
      on_settlement    → disburse from trust
```

The method reactors hold the multi-step branch bodies.

| Reactor | Shape |
|---|---|
| `Auction` | Reserve set → await hammer → unconditional immediately. Passed-in falls through to `PrivateTreaty` |
| `SetDateSale` | Await offer deadline → `map` + `dispatch` a `Negotiation` per offer → vendor picks → cancel the losers |
| `PrivateTreaty` | Single `Negotiation` child |
| `Negotiation` | Offer → await response → `switch` on accept / counter / reject / lapse |

### Sale attempts and the generation chain

A contract can die after exchange: rescission in cooling off, a condition failing, a buyer
defaulting at settlement. What survives is everything the agent built — the compliance gate
holds, the campaign holds, the agency agreement runs on, and the buyer register keeps the
underbidders. Campaigns resume.

A failed attempt therefore dispatches its successor:

```
Engagement
  dispatch :sale_attempt        → SaleAttempt generation 1
                                    on failure: dispatch :next_attempt
                                      → SaleAttempt generation 2 (register minus the buyer)
                                        on failure: dispatch :next_attempt
                                          → …
                                    on settlement: report up
```

Each generation is a different parent, so derived child ids never collide and the chain is
unbounded without a counter threaded through the graph. Generation 2 onward is a private
treaty against the register, which is what agents do.

Failure consequences differ, and the example turns on them.

| Failure | Deposit | Accrued commission |
|---|---|---|
| Rescinded in cooling off | Forfeit at the state's rate to the vendor, balance refunded | Written back |
| Condition failed | Refunded in full | Written back |
| Buyer default at settlement | Forfeited | **Paid from the forfeited deposit** |

The last is the case where a sale that never completed still earns.

### Points the prototype settled

- **Branch lanes persist.** After a `switch` resolves, all three method lanes stay on
  screen with the untaken ones ghosted. Showing only the taken path loses the argument.
- **Conditions fan out.** Finance, inspection and title resolve independently and in any
  order, and the attempt advances when all three land. It is a fan-out inside the
  `dispatch`, and each has its own failure path.
- **The vendor's decision window is bounded.** Children hold live offers with expiries, so
  the await after the map carries a timeout computed from the shortest live offer.

## Commission

Accrual and discharge are separate events.

- **Entitlement** accrues when the agent is the effective cause of a binding sale, at
  exchange. It survives an agency term expiring mid-campaign.
- **Payment** is triggered by the agreement's terms: `:on_settlement` deducts from the
  deposit held in trust, `:on_unconditional` brings it forward.

`Commission` carries `accrued_at` and `disbursed_at` as distinct columns, and the terminal
`switch` reads the trigger.

The prototype showed this is the example's most legible surface. The product view leads
with a single figure and what it is waiting on — "Payable on settlement, due 20 Nov"
becoming "Paid 20 Nov" — with written-back and forfeited amounts beside it. Treat that
panel as a first-class deliverable.

## Jurisdiction

`Agency.Sale.Jurisdiction` exposes `gate_for/2`, returning a reactor module, and
`cooling_off/1`, returning a policy.

| | NSW | VIC | QLD |
|---|---|---|---|
| Pre-marketing gate | Contract + prescribed documents | Vendor statement + Statement of Information | Form 6 appointment + seller disclosure |
| Cooling off | 5 business days, 0.25% forfeit | 3 business days, 0.2% forfeit | 5 business days, 0.25% forfeit |
| Auction exemption | Yes | Yes, extending to day before and day of | Yes |

The NSW gate is the strongest await in the example: a property legally cannot be marketed
until the vendor's solicitor has a contract prepared with prescribed documents attached.
The campaign waits on a third party the agent has no control over.

Adding a state is a new module and a new enum value.

## Data model

Ash resources under `Agency.Sale`.

| Resource | Carries |
|---|---|
| `Property` | Address, `jurisdiction` |
| `AgencyAgreement` | Vendor, agent, `appointment`, term, rate, `commission_trigger`, `sale_method` |
| `ComplianceDocument` | Kind, received_at |
| `SaleAttempt` | Generation, opened_at, closed_at, `outcome`, predecessor |
| `Buyer` | Name, conveyancer, lender, `register_status` |
| `Offer` | Buyer, attempt, amount, requested conditions, expiry, `status`, `supersedes` |
| `Contract` | Attempt, buyer, price, deposit, exchanged_at, unconditional_at, settlement_date |
| `Condition` | Contract, kind, due, `status` |
| `Deposit` | Amount, held_in, `status`, forfeited_to |
| `Commission` | Attempt, accrued_at, payable_on, amount, disbursed_at, `outcome` |

`Offer.supersedes` is self-referential, so a negotiation reads back as a chain.
`SaleAttempt.predecessor` is self-referential, so the generation chain does too.

Statuses are `Ash.Type.Enum` modules, following the payouts pattern. Enumerated types carry
the closed sets: `:exclusive | :sole | :open`, `:on_settlement | :on_unconditional`,
`:auction | :set_date | :treaty`, `:finance | :inspection | :title`,
`:settled | :rescinded | :condition_failed | :buyer_default | :no_offers`.

Jurisdiction stays a module.

The four generated magma resources live under `Agency.Magma`.

## Awaits and third parties

| Entity | Used for | Reason |
|---|---|---|
| `await` | Vendor accepts or counters, buyer responds, auction hammer, buyer cools off, vendor withdraws | A person decides |
| `poll` | Lender finance status, title searches, PEXA settlement | An external system holds queryable state |

Timeouts carry domain meaning. The offer deadline in a set date sale is an await timeout, as
is the agency term expiring beneath the campaign await, and the vendor's decision window
beneath the map.

Simulated parties, one module each over DB-backed state: `Agency.Conveyancer`,
`Agency.Lender`, `Agency.Titles`, `Agency.Pexa`.

## Time

Cooling-off runs in business days against state public holidays, so `Agency.Sale.Clock`
computes deadlines against a per-jurisdiction holiday calendar. A `:time_scale` config
compresses wall-clock for the demo while the arithmetic stays real.

The demonstration to preserve: the same exchange date yields different cooling-off expiries
across states, because NSW and QLD both hold a public holiday on the first Monday of
October and VIC does not.

## The two views

Kept separate. Merging them produced an operations console.

**`listing_live` — the agent's sales desk.** Speaks the agent's language throughout:
offers, buyers, cooling off, settlement, commission. Listing picker, the listing itself, and
a commission panel. A stage strip reads as a sale progression, and its labels change with
the method. A listing whose contract fell through shows a banner, the failed contract in
its own card, and buttons to re-approach each underbidder.

No workflow vocabulary appears on this screen.

**`console_live` — the workflow inspector.** Matches payouts and helpdesk: running
workflows, checkpoints, pending signals, the branch each `switch` took, and the generation
chain as parent and children. This is where a developer reads what magma did.

**Seeded fixtures.** A `mix` task seeds several listings at deliberately different points —
one at an offer deadline, one at auction, one mid cooling-off paying on unconditional, one
already fallen through with underbidders waiting. Branching is legible immediately, without
playing a listing forward to reach an interesting state.

## Tests

In priority order.

1. **`dispatch` inside `recurse` yields distinct children.** The prerequisite, written first
   and failing.
2. **Replay determinism across a branch.** Kill mid-branch, replay, confirm resumption at
   the edge and re-entry into the same branch.
3. Each sale method reaches exchange. Cooling-off applies for treaty and set date, and is
   exempt for auction.
4. Set date sale cancels losing negotiation children on exchange, and the vendor's decision
   window expires with the shortest live offer.
5. Conditions satisfy in any order and the attempt advances only when all three land.
6. The generation chain: a rescission opens generation 2 against the surviving register,
   and the two generations hold distinct child ids.
7. Each failure's commission consequence — written back on rescission and condition
   failure, paid from the forfeited deposit on buyer default.
8. Gate resolution per jurisdiction, with business-day arithmetic crossing a state holiday.
9. Both commission triggers disburse at the right moment.
10. Engagement-level terminals: term expiry, vendor withdrawal, register exhausted.

## Scope

Everything above: three jurisdictions, three sale methods, the generation chain, seeded
listings, both views. The largest example in the repo.

Sequenced so the prerequisite lands first, then the reactors, then the resources, then the
two views.
