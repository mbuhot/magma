# Helpdesk — actor and tenant through a durable workflow

An agent asks for a ticket to be escalated. Somebody decides. If it is approved the ticket
moves; if it is rejected it goes back where it was.

The run is told who it is acting as, and for which organisation, exactly once:

```elixir
Magma.start(Workflow, %{ticket_id: ticket.id, reason: reason},
  actor: %{id: agent.id},
  tenant: organisation.id
)
```

Nothing after that line names either again.

## The idea

**The row holds an identity. The policies read a calculation.**

```
workflow row      %{id: user_id}                          persisted, cannot go stale
      ↓
Rehydrate.init/1  Ash.get(User, id, load: [:permissions]) every attempt
      ↓
context.actor     a User whose permissions were read just now
      ↓
policy            :reassign_tickets in ^actor(:permissions)
```

Ash never loads an actor's fields on demand — an unloaded path raises. So the load happens in
a `Reactor.Middleware`, which `Reactor.run/4` calls once per attempt before the first step, and
which magma calls again before driving any `undo/4`.

A run parked overnight therefore authorizes against the grants that stand in the morning.

## The workflow

`lib/helpdesk/support/escalation/workflow.ex` is the whole sequence.

```
ticket      read the ticket, scoped by the tenant
assess      a plain step, reading context.actor and context.tenant by hand
raise       record the escalation — anybody may ask
approval    wait for a decision, up to 24 hours
reassign    move the ticket — needs :reassign_tickets
notify      write the audit entry
outcome     a rejection is an error, and the run unwinds
```

The demonstration is the gap either side of the wait. Same actor, same run, two different
answers — decided after the park, not before it.

## What the engine provides instead of application code

| Requirement | How |
|---|---|
| Every step runs as the caller | magma seeds `actor` and `tenant` from the row on each attempt |
| No step passes them along | `Ash.Reactor` reads both off the reactor context |
| Another organisation's ticket is invisible | attribute multitenancy scopes `:ticket`, which fails on not found |
| Authority is current | `:permissions` is a calculation, loaded fresh by the middleware |
| A refused step takes back what was done | `:raise` has an undo, so the escalation is withdrawn |
| A rejection restores the ticket | `:reassign` has an undo, driven from the checkpoint it recorded |
| A rollback authorizes as the same actor | magma runs the middleware before unwinding, too |

## Permissions

Two sources, so authority can move either way in a test or by hand:

| Source | Holds `:reassign_tickets` |
|---|---|
| `role: :manager` | always |
| a `Grant` row | while the row exists |

`Helpdesk.Accounts.Calculations.Permissions` is the union of the two.

## The console

`http://localhost:4000` is a LiveView over the same store the engine writes to.

- **`/`** — switch organisation and user, and every query on the page is scoped and authorized
  by that pair, exactly as the workflow is. Raise an escalation, grant or revoke
  `:reassign_tickets`, and see what a second organisation sees at the same moment.
- **`/escalations/:id`** — the tape, what the row holds beside what that identity may do right
  now, and the approve / reject buttons.

To see the point by hand: raise an escalation as Ada, leave it parked, grant her
`:reassign_tickets`, then approve. Do it again without the grant and watch the run fail and
the escalation disappear.

## Run it

Needs Postgres on `localhost:5432` (`postgres`/`postgres`).

```sh
mix setup
mix test
mix run --no-halt
```

`mix setup` seeds two organisations: Northwind (Ada, an agent; Grace, a manager) and Contoso
(Bea).

## The tests

```
an escalation waits for a decision before the ticket moves anywhere
a manager's approval moves the ticket to whoever was named
the run records every step it finished
a plain step reads the actor and the tenant off the context
the audit entry names the person the run acted as
a permission granted while the run was parked lets it finish
an actor holding no such permission cannot move the ticket
a permission taken back while the run was parked stops it
an escalation nobody may act on is withdrawn when the run unwinds
a rejected escalation puts the ticket back where it was
the role a user holds grants the same permission a grant does
a run cannot reach a ticket belonging to another organisation
the run reads the tenant it was started for, not whichever was last used
the actor and the tenant come back after the run has been parked
the workflow row holds an identity and nothing that can go stale
an escalation another organisation raised is not on our audit trail
the queue shows only the organisation that is selected
an agent can raise an escalation and land on its page
an agent holding nothing cannot get the ticket moved
granting the permission while the run waits lets the same approval through
the run's page shows the identity it holds and the authority that identity has now
```
