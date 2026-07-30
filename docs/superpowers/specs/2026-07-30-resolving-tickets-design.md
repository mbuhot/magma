# Resolving tickets in the helpdesk example

## Problem

The helpdesk example carries a `:closed` ticket status that nothing ever sets. Every run in the
example ends by being decided, so cancellation — the third way a durable run can end — goes
undemonstrated.

Resolving a ticket supplies both: a terminal ticket state, and a reason for the engine to
unwind a run that nobody decided.

## Decisions

| Decision | Rationale |
|---|---|
| Anybody in the tenant may resolve | keeps `:reassign_tickets` the example's single permission |
| `:closed` is terminal | one control, one story |
| Resolving cancels a waiting escalation | the new thing the engine does here |
| Cancellation reuses `:raise`'s undo | `undo_action(:withdraw)` already exists |

## Domain

`Ticket.resolve` — an update action setting `status` to `:closed`, authorized by
`authorize_if always()`, exposed on the `Support` domain as `resolve_ticket`.

`Workflow.abandon/1` — takes a ticket, finds its latest run through the existing
`latest_for/1`, and calls `Magma.cancel/1` when that run is waiting. Runs that completed,
failed or were already cancelled are left alone.

## Order

The ticket page's `resolve` event abandons the run, then closes the ticket.

A waiting run has only `:raise` behind it. Its unwind withdraws the escalation row and leaves
the ticket alone, so the two writes stay off each other's rows.

```
resolve clicked
      ↓
Workflow.abandon(ticket)   waiting run → Magma.cancel/1 → undo :raise → escalation withdrawn
      ↓
Support.resolve_ticket     status → :closed
```

## Console

| Where | What |
|---|---|
| Ticket page | a "Resolve" button beside the status chip while the ticket is unclosed |
| Ticket page, run waiting | that button reads "Resolve and drop the escalation" |
| Ticket page, closed | the escalation form and the decision controls are gone |
| Queue, "Assigned to me" | the ticket stays, carrying a `closed` chip |
| Queue, "Open across the team" | `open_in_team` already filters `:closed` out |

## Tests

- resolving a ticket closes it and takes it off the team's open list
- resolving a ticket whose escalation is waiting withdraws that escalation
- a closed ticket offers nobody an escalation
