# Helpdesk — actor and tenant through a durable workflow

A second example application, beside `examples/payouts`. Payouts shows durability: the
checkpoint, the park, the rollback. Helpdesk shows the Ash seam — an actor and a tenant
named once at the call site and honoured by every step, across a park of days and a
later attempt in a different job.

## Table of contents

- [What it demonstrates](#what-it-demonstrates)
- [The domain](#the-domain)
- [Policies](#policies)
- [The workflow](#the-workflow)
- [The actor is a snapshot](#the-actor-is-a-snapshot)
- [The console](#the-console)
- [Tests](#tests)
- [Layout](#layout)
- [Milestones](#milestones)

## What it demonstrates

| Claim | Shown by |
|---|---|
| Actor and tenant are named once | `Magma.start/3` at the call site; no step declares either |
| Every Ash step inherits them | `read_one`, `create` and `update` steps run authorized with no plumbing |
| They survive the job boundary | the run parks on `await`, resumes in a later job, and still reads the same tenant |
| A plain step can read them | `:assess` takes them off `context` by hand |
| Tenancy isolates | a workflow started for one organisation cannot read another's ticket |
| Policies bite | an agent's approval is `Ash.Error.Forbidden`, and the run unwinds |
| Unwinding carries them too | the compensating update authorizes as the same actor |
| The actor is a snapshot | a step reloads the user when a role changed during the park |

## The domain

Two domains. Everything but the organisation is multitenant by attribute on `org_id`.

| Domain | Resource | Multitenant | Holds |
|---|---|---|---|
| `Helpdesk.Accounts` | `Organisation` | no | `name` — the tenant itself |
| `Helpdesk.Accounts` | `User` | yes | `name`, `role :: :agent \| :manager` — the actor |
| `Helpdesk.Support` | `Ticket` | yes | `subject`, `status`, `priority`, `assignee_id` |
| `Helpdesk.Support` | `Escalation` | yes | `ticket_id`, `raised_by_id`, `approved_by_id`, `reason`, `decision` |
| `Helpdesk.Support` | `AuditEntry` | yes | `action`, `actor_name`, `at` |

Multitenancy is `strategy: :attribute, attribute: :org_id`, with
`global? false` so a query missing its tenant is an error rather than a silent read
across organisations. That is what makes the isolation test unambiguous.

## Policies

| Resource | Action | Rule |
|---|---|---|
| `Ticket` | `:read` | any authenticated actor (tenancy does the scoping) |
| `Ticket` | `:reassign` | `actor.role == :manager` |
| `Escalation` | `:raise` | any authenticated actor |
| `Escalation` | `:approve` | `actor.role == :manager` |
| `AuditEntry` | `:create` | any authenticated actor |

A bare `authorize_if always()` on read keeps the sample's point on tenancy and on the two
manager-only actions.

## The workflow

`Helpdesk.Support.Escalation.Workflow`, queue `:escalations`.

```
ticket        read_one Ticket by id, fail_on_not_found?
assess        plain step — reads context.actor and context.tenant itself
raise         create Escalation (an agent may raise)
approval      await "decision", timeout 24h — the run parks here
approver      read_one User by the approval's user id — the fresh role
reassign      update Ticket, :reassign — manager only, with undo
notify        create AuditEntry
```

```elixir
{:ok, workflow} =
  Magma.start(
    Helpdesk.Support.Escalation.Workflow,
    %{ticket_id: ticket.id, reason: "customer waiting three days"},
    actor: agent,
    tenant: org.id
  )
```

`actor:` and `tenant:` appear in that call and nowhere else. No step declares an `actor`
entity, no step takes a tenant argument, and no step threads either through its
arguments. `Ash.Reactor` reads both off the reactor context, which magma seeds from the
workflow row on every attempt.

`:reassign` implements `undo/4`, restoring the previous assignee. A rejected decision
fails the run, so the rollback is what puts the ticket back — authorizing as the same
actor, from the same tenant, out of `Magma.Unwind`.

`:assess` is a plain `step` with no Ash entity at all. It pattern-matches `context.actor`
and `context.tenant` to decide the escalation's priority, which is how a non-Ash step
reaches the same two values.

## The actor is a snapshot

`actor:` is stored as a term on the workflow row, fixed at the moment the workflow
starts. A run parked for a day carries the actor as it stood a day ago.

The workflow shows both sides of that. `:raise` authorizes against the snapshot, which is
right — the agent's authority to raise was established when they raised it. `:approver`
re-reads the approving user before `:reassign` runs, because a role granted or revoked
during the park must be honoured. The README states the rule: authorize the request
against the snapshot, and reload whenever a decision turns on authority as it stands now.

## The console

LiveView on `http://localhost:4000`, over the same store the engine writes.

| Route | |
|---|---|
| `/` | organisation and user switchers, the current tenant's tickets, a form to raise an escalation, and a panel showing what a second organisation sees at the same moment |
| `/escalations/:id` | the tape, the actor and tenant the run carries, and approve / reject buttons |

The switchers set the session's actor and tenant; every query the console makes passes
them, so the page itself is subject to the same policies as the workflow. Approve and
reject are one call to `Magma.signal/3`.

## Tests

Behaviour, in the payouts example's style.

```
runs every step as the actor and tenant the caller named
keeps the actor and tenant across a park and a later attempt
cannot read a ticket belonging to another organisation
refuses to reassign for an agent, and unwinds
puts the assignee back when the decision is a rejection
honours a role granted during the park
records an audit entry naming the actor
names the actor and tenant only at the call site
produces the tape the lifecycle describes
```

The last one is `tape/1` from `Magma.Testing`. The isolation test starts a workflow for
one organisation against a ticket created in another and asserts the run fails at
`:ticket`.

## Layout

```
examples/helpdesk/
  lib/helpdesk/
    application.ex  repo.ex
    accounts.ex
    accounts/            organisation.ex  user.ex  role.ex
    support.ex
    support/             ticket.ex  escalation.ex  audit_entry.ex
                         ticket_status.ex  decision.ex
                         escalation/workflow.ex  escalation/steps.ex
    magma/               generated store resources
  lib/helpdesk_web/      endpoint.ex  router.ex  layouts.ex
                         live/console_live.ex  live/escalation_live.ex
  test/helpdesk/         escalation_test.exs  isolation_test.exs
  test/helpdesk_web/     console_test.exs
  README.md
```

Deps and aliases mirror `examples/payouts/mix.exs`: `{:magma, path: "../.."}`,
`ash_postgres`, `oban`, `phoenix`, `phoenix_live_view`, `bandit`, `lazy_html` for tests.
`mix setup` creates and migrates; `mix test` migrates first.

The magma store resources come from `mix igniter.install magma`, as a real application
would get them.

## Milestones

1. **Project skeleton** — mix project, repo, config, application, magma install, migrations.
2. **Domain** — the five resources with their tenancy, policies and actions, plus seeds.
3. **Workflow** — the seven steps, the undo on `:reassign`, and `escalation_test.exs`.
4. **Isolation and authority** — the cross-tenant test, the forbidden-approval test, the
   role-changed-during-park test.
5. **Console** — the two LiveViews and `console_test.exs`.
6. **README** — the tour, the table of claims, and the snapshot rule.
