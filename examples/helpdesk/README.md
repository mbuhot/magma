# Helpdesk — actor and tenant through a durable workflow

A small ticketing app for two companies. An agent asks for a ticket to be escalated, a team
lead decides it, and the ticket moves or stays where it was.

Pick an organisation and a person in the top bar, and the whole app is that pair: the queue is
theirs, the tickets are their company's, and what they can do is what their role and their
grants say. It is the same pair a durable run is given, doing the same job.

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
decider     read the person who decided, with the authority they hold now
reassign    move the ticket — as the decider, who needs :reassign_tickets
notify      write the audit entry, as the decider
outcome     a rejection is an error, and the run unwinds
```

Most steps inherit the actor from the run — the person who asked. Moving the ticket is
somebody else's authority, so `:reassign` names `:decider` as its actor. That is the one
place a step states an actor, and only because the domain says so.

Whether the decider may act is read on the attempt that wakes, never when the run parked.

## What the engine provides instead of application code

| Requirement | How |
|---|---|
| Every step runs as the caller | magma seeds `actor` and `tenant` from the row on each attempt |
| No step passes the tenant along | `Ash.Reactor` reads it off the reactor context |
| A decision carries its own authority | `:reassign` takes `actor result(:decider)` |
| Another organisation's ticket is invisible | attribute multitenancy scopes `:ticket`, which fails on not found |
| Authority is current | `:permissions` is a calculation, loaded fresh by the middleware |
| A refused step takes back what was done | `:raise` has an undo, so the escalation is withdrawn |
| A rejection restores the ticket | `:reassign` has an undo, driven from the checkpoint it recorded |
| A rollback authorizes as the same actor | magma runs the middleware before unwinding, too |

## Permissions

Two sources, so authority can move either way in a test or by hand:

| Source | Holds `:reassign_tickets` |
|---|---|
| `role: :team_lead` | always |
| a `Grant` row — "cover" in the app | while the row exists |

`Helpdesk.Accounts.Calculations.Permissions` is the union of the two.

## The console

`http://localhost:4000` is a LiveView over the same store the engine writes to.

- **`/`** — the queue. Tickets assigned to whoever is signed in, or everything open across
  their team. Team leads also see who can act on escalations, and can give an agent cover.
- **`/tickets/:id`** — one ticket, its history, and whatever it is waiting on. Anybody can ask
  for an escalation; only somebody who can act on one is offered the decision.

Three things to try:

1. **Switch person.** Ada and Ben hold different tickets. The queue is whoever you are.
2. **Switch organisation.** Northwind's people vanish and Contoso's appear, because a user
   belongs to a tenant like everything else.
3. **Ask, then change who may answer.** As Ada, request an escalation — it parks, and she is
   told a team lead has to decide. As Grace, give Ada cover. Go back to Ada's ticket: the
   decision is hers to make now, on a run that was already waiting.

## Run it

Needs Postgres on `localhost:5432` (`postgres`/`postgres`).

```sh
mix setup
mix test
mix run --no-halt
```

`mix setup` seeds two companies. Northwind Traders has Ada and Ben answering tickets and Grace
leading them; Contoso Freight has Bea and Carlos, led by Dana.

## The tests

```
an escalation waits for a decision before the ticket moves anywhere
a team lead's approval moves the ticket to whoever was named
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
somebody sees the tickets they are holding
switching person shows that person's queue instead
switching organisation offers that organisation's people
the team tab shows everything open, not only your own
an agent is not shown who can act on escalations
a team lead can give an agent cover, and take it back
an agent can ask for an escalation
an agent is not offered the decision
a team lead is offered the decision on somebody else's request
approving moves the ticket to whoever the team lead picked
declining leaves the ticket with whoever had it
an agent given cover while their request waits can then decide it themselves
the history says what happened, in the order it happened
```
