# Property Sale — a branching example

## Why

The existing examples each carry one theme.

| Example | Theme |
|---|---|
| `payouts` | Money movement, compensation, rails |
| `helpdesk` | Identity, actor, tenant, derived authority |
| `agency` | **Branching and long human awaits** |

Neither existing example uses `switch`. This one is built around it, and around the
question of which construct answers "it depends" in each situation.

## Domain

A real estate agent's engagement, from the signing of an agency agreement through to
commission disbursed. No single production system spans this: the agent's CRM stops at
contract, conveyancing software starts there, the lender and PEXA sit outside both. The
example app is the transaction coordinator across all of them, which is the orchestration
job that durable workflows exist for.

Jurisdiction is NSW, VIC and QLD.

## Three answers to "it depends"

The example's argument is that these are different problems.

| Decision | Construct | Why |
|---|---|---|
| Sale method | `switch` with composed branches | Few branches, each a structurally different flow |
| Jurisdiction | Runtime-resolved `dispatch` | Many branches, uniform shape, grows per state |
| Cooling-off | Small inline `switch` | Two outcomes, decided by resolved policy |

## Workflow shape

Five reactors.

```
Agency.Sale.Engagement                     ← parent, one per agency agreement
  agency agreement accepted
  dispatch :compliance_gate                ← module resolved from jurisdiction
  step   :launch_campaign
  await  :campaign_outcome                 ← escapes: withdrawn / term expired
  ▸ switch on sale_method
      auction    → compose Agency.Sale.Auction
      set_date   → compose Agency.Sale.SetDateSale
      treaty     → compose Agency.Sale.PrivateTreaty
  ← branches rejoin, each returning an exchanged contract
  ▸ switch on cooling_off policy
      applies    → await :cooling_off_expiry, timeout from policy
      exempt     → pass through            (auction lands here)
  dispatch :conditions                     ← finance / inspection / title
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
| `PrivateTreaty` | Single `Negotiation` child, `recurse` on counter-offers |
| `Negotiation` | Offer → await response → `switch` on accept / counter / reject / lapse; counter recurses |

### Parent and child

`dispatch` supplies this today. It derives a stable child id from parent plus step name,
starts the child idempotently, and parks the parent until the child reports. `map`
generates step names carrying an index, so `dispatch` inside `map` yields distinct
children.

The constraint that follows: the set of children is fixed by the graph. Offers arriving
over time as signals would collide on child id. Sale method resolves this, because the
method determines the offer topology.

| Method | Offer topology | Fan-out |
|---|---|---|
| Auction | Bidding is external; one buyer at the hammer | None |
| Set date sale | Offers collect as data until a deadline | `map` + `dispatch` |
| Private treaty | The agent works one offer at a time | Single child |

## Commission

Accrual and discharge are separate events.

- **Entitlement** accrues when the agent is the effective cause of a binding sale, at
  exchange. This is what survives an agency term expiring mid-campaign.
- **Payment** is triggered by the agreement's terms: `:on_settlement` deducts from the
  deposit held in trust, `:on_unconditional` brings it forward.

`Commission` carries `accrued_at` and `disbursed_at` as distinct columns, and the terminal
`switch` reads the trigger.

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
| `Buyer` | Name, conveyancer, lender |
| `Offer` | Buyer, amount, requested conditions, expiry, `status`, `supersedes` |
| `Contract` | Buyer, price, deposit, exchanged_at, unconditional_at, settlement_date |
| `Condition` | Contract, kind, due, `status` |
| `Deposit` | Amount, held_in, `status` |
| `Commission` | accrued_at, payable_on, amount, disbursed_at |

`Offer.supersedes` is self-referential, so a negotiation reads back as a chain.

Statuses are `Ash.Type.Enum` modules, following the payouts pattern. Enumerated types
carry the closed sets: `:exclusive | :sole | :open`, `:on_settlement | :on_unconditional`,
`:auction | :set_date | :treaty`, `:finance | :inspection | :title`.

Jurisdiction stays a module rather than a resource.

The four generated magma resources live under `Agency.Magma`.

## Awaits and third parties

| Entity | Used for | Reason |
|---|---|---|
| `await` | Vendor accepts or counters, buyer responds, auction hammer, buyer cools off, vendor withdraws | A person decides |
| `poll` | Lender finance status, title searches, PEXA settlement | An external system holds queryable state |

Timeouts carry domain meaning. The offer deadline in a set date sale is an await timeout,
as is the agency term expiring beneath the campaign await.

Simulated parties, one module each over DB-backed state: `Agency.Conveyancer`,
`Agency.Lender`, `Agency.Titles`, `Agency.Pexa`. The console drives them.

## Time

Cooling-off runs in business days against state public holidays, so
`Agency.Sale.Clock` computes deadlines against a per-jurisdiction holiday calendar. A
`:time_scale` config compresses wall-clock for the demo while the arithmetic stays real.

## Console

Two LiveViews, following the existing examples.

- **`console_live`** — every running engagement, its current await, the branch it took.
- **`listing_live`** — one engagement end to end: step timeline, branch point with
  untaken paths greyed, pending awaits as buttons, third-party control panel.

The same listing under auction and under set date sale should look visibly different.
That contrast is the example's argument.

## Tests

In priority order.

1. **Replay determinism across a branch.** Kill mid-branch, replay, confirm resumption at
   the edge and re-entry into the same branch.
2. Each sale method reaches exchange. Cooling-off applies for treaty and set date, and is
   exempt for auction.
3. Set date sale cancels losing negotiation children on exchange.
4. Negotiation recursion terminates on accept, reject and lapse.
5. Gate resolution per jurisdiction, with business-day arithmetic crossing a state
   holiday.
6. Both commission triggers disburse at the right moment.
7. Death paths: term expiry, vendor withdrawal, finance condition failure, buyer default
   with deposit forfeiture.

## Risk to resolve first

The design rests on one unverified claim: that reactor's `switch` composes with magma's
checkpointing such that a replay re-enters the branch it originally took. `switch`
predicates read checkpointed results, which is the reason to expect it holds.

**The implementation plan opens with a spike confirming this.** A negative result is worth
more than the example, and would change the example's shape.

## Scope

The largest of the three examples: five reactors, three jurisdiction modules, four
simulated parties, nine resources, two LiveViews. Roughly 2–3× helpdesk.

Deferrable to a second pass if it runs long:

- QLD, leaving NSW and VIC to establish the resolver pattern
- The private treaty branch, leaving auction and set date to carry the contrast
