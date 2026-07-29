# Payouts — a durable offramp on magma

A customer asks for their balance to be paid out. The service prices it, waits for them to
confirm, takes the money, hands it to a bank rail, and waits for settlement.

Every step of that is a checkpoint. Kill the process anywhere in it and the run picks up from
where it stopped, without pricing twice, debiting twice, or sending twice.

## The workflow

`lib/payouts/offramp/payout.ex` holds the sequence and nothing else.

```
transfer      load what was asked for
onboarding    check the rail has taken this customer on
beneficiary   check the rail holds an account to pay, where the rail needs one
quote         price it with the provider
confirmation  wait for the customer — up to 15 minutes, then the quote has lapsed
debit         take the money, with an undo that gives it back
rail          dispatch the rail that serves the currency, as a child workflow
settlement    wait for the rail — up to 24 hours
settle        mark it done, or fail and unwind
```

## The rails

The spine names no provider. `:rail` dispatches a **child workflow** whose module
`Payouts.Routing` resolves from the transfer's currency, running on the `rails` queue with
its own row and its own job.

| Rail | Currency | Payout | KYC | Beneficiary |
|---|---|---|---|---|
| **Bridge** | EUR | fund a vault, then send | nine steps, every document Bridge asks for | register the account with Bridge first |
| **Meridian** | USD | send | two steps, no documents | none — it pays the customer's own account |

Three columns of difference, and the spine is unchanged by any of them. Each is a config entry
pointing at a workflow, and `:beneficiary` in the spine asks config whether a registration is
wanted before it insists on one. Adding a currency to the `:rails` config routes the next
payout to it.

The child's id is derived from the spine and the dispatching step, so a spine that comes back
after a crash adopts the rail already running rather than starting a second one. The module
is decided at run time; only the identity has to be stable.

## What the engine provides instead of application code

| Requirement | How |
|---|---|
| The quote shown is the amount debited | `debit` reads `quote`'s recorded output, so a replay cannot re-price |
| The customer is debited once | the debit's checkpoint is what a resumed run replays |
| A quote that lapses is an error | the confirmation wait's deadline *is* the quote's expiry |
| A rejected payout gives the money back | `debit` implements `undo/4`, and a rejection fails the run |
| A payout waiting for days costs nothing | a parked workflow is a row, holding no process |
| The rail is whichever serves the currency | `:rail` dispatches a child workflow chosen from config |
| Only a customer the rail has taken on is paid | `:onboarding` and `:beneficiary` both stand in front of `:quote` |

## The console

`http://localhost:4000` is a LiveView over the same store the engine writes to. It reads
checkpoints; it holds nothing of its own.

- **`/`** — fund a customer, run a rail's KYC, register an account, ask for a payout. Panels
  for what each rail is configured with and for arming the provider to refuse a call once.
- **`/payouts/:id`** — the tape. One row per completed step with the value it recorded, the
  rail's own tape beneath it, the ledger, and what the run is parked on.

The two buttons on the right are the two moments a payout waits on somebody: the customer
approving the quote before the rail is invoked, and the rail's webhook saying how it went.
Both are one call to `Magma.signal/3`.

## Run it

Needs Postgres on `localhost:5432` (`postgres`/`postgres`).

```sh
mix setup
mix test
mix run --no-halt
```

The provider is stood in for by `Payouts.Provider`, which records every call and can be told
to fail. Its rate moves on every call, so a test can see whether a replayed quote re-priced.

## The tests

```
waits for confirmation before touching the balance
debits and reaches the provider once confirmed
completes on settlement
holds the quoted amount even after the price moves
prices once and sends once when the run resumes after a crash
does not debit twice when the provider is down
gives the money back when the rail rejects
runs the rail config says serves the currency
runs a differently shaped rail for a different currency
names no rail in the spine
produces the tape the lifecycle describes
refuses a customer the rail has never been told about
refuses one whose KYC is still undecided
refuses one onboarded on a different rail
refuses a payout to an account the rail was never told about
refuses one the rail has not accepted yet
asks for no beneficiary on a rail that pays the customer's own account
tells the rail to pay the account that was registered
```
