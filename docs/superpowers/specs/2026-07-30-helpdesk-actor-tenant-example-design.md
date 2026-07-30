# Helpdesk — actor and tenant through a durable workflow

A second example application, beside `examples/payouts`. Payouts shows durability: the
checkpoint, the park, the rollback. Helpdesk shows the Ash seam — an actor and a tenant
named once at the call site and honoured by every step, across a park of days and a
later attempt in a different job.

Its central idea: **the workflow persists identity, and derives authority.** What goes on
the row is who this is. What the policies read is a permission calculation, evaluated
afresh on every attempt, so a run parked for a day authorizes against the grants that
stand when it wakes.

## Table of contents

- [What it demonstrates](#what-it-demonstrates)
- [The domain](#the-domain)
- [Identity persisted, authority derived](#identity-persisted-authority-derived)
- [Policies](#policies)
- [The workflow](#the-workflow)
- [The magma change](#the-magma-change)
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
| Permissions are current, not frozen | a grant made during the park lets the post-park step through |
| Policies bite | an actor without the grant gets `Ash.Error.Forbidden`, and the run unwinds |
| Unwinding carries them too | the compensating update authorizes as the same rehydrated actor |

## The domain

Two domains. Everything but the organisation is multitenant by attribute on `org_id`.

| Domain | Resource | Multitenant | Holds |
|---|---|---|---|
| `Helpdesk.Accounts` | `Organisation` | no | `name` — the tenant itself |
| `Helpdesk.Accounts` | `User` | yes | `name`, `role :: :agent \| :manager` |
| `Helpdesk.Accounts` | `Grant` | yes | `user_id`, `permission` — a capability held |
| `Helpdesk.Support` | `Ticket` | yes | `subject`, `status`, `priority`, `assignee_id` |
| `Helpdesk.Support` | `Escalation` | yes | `ticket_id`, `raised_by_id`, `reason` |
| `Helpdesk.Support` | `AuditEntry` | yes | `action`, `actor_name`, `at` |

Multitenancy is `strategy: :attribute, attribute: :org_id`, with `global? false` so a
query missing its tenant is an error rather than a silent read across organisations. That
is what makes the isolation test unambiguous.

`User` carries a calculation:

```elixir
calculate :permissions, {:array, :atom}, Helpdesk.Accounts.Calculations.Permissions
```

It is derived from the role and the user's `Grant` rows — a manager holds
`:reassign_tickets` by virtue of the role, and an agent holds whatever has been granted.
Two sources, so the test can move authority either way.

## Identity persisted, authority derived

Ash does not lazily load actor fields. `relates_to_actor_via` raises `ArgumentError:
Actor field is not loaded` on an unloaded path
(`deps/ash/lib/ash/policy/check/relates_to_actor_via.ex:90`), and `^actor(:permissions)`
reads whatever sits on the struct — an `%Ash.NotLoaded{}` if nothing loaded it. So
something must load the actor before any step runs.

`Reactor.Middleware.init/1` returns a modified context
(`deps/reactor/lib/reactor/middleware.ex:93`), and magma calls `Reactor.run/4` afresh on
every attempt. So a middleware runs exactly once per attempt, before any step, and the
context it rewrites propagates into async steps through Reactor's own process-context
copying.

```
workflow row      %{id: user_id}                       identity — small, stable, never stale
      ↓
Rehydrate.init/1  Ash.get(User, id, load: [:permissions])    every attempt
      ↓
context.actor     a User with permissions calculated now
      ↓
policies          authorize_if expr(:reassign_tickets in ^actor(:permissions))
```

`Helpdesk.Accounts.Rehydrate` is an ordinary `Reactor.Middleware` in the example
application, added to the workflow with the `middlewares` DSL section. Magma has no
special knowledge of it. `User` is multitenant, so the middleware reads the tenant off the
same context it is rewriting — the tenant is already there, seeded from the row.

An identity that no longer resolves is an error: a deleted user fails the attempt rather
than running the workflow unauthenticated.

The rule the README teaches: **persist what identifies, calculate what authorizes.** The
snapshot on the row carries only what cannot go stale.

## Policies

| Resource | Action | Rule |
|---|---|---|
| `Ticket` | `:read` | `authorize_if always()` — tenancy does the scoping |
| `Ticket` | `:reassign` | `expr(:reassign_tickets in ^actor(:permissions))` |
| `Escalation` | `:raise` | `authorize_if always()` |
| `AuditEntry` | `:create` | `authorize_if always()` |
| `Grant` | `:read` | `authorize_if always()` |

Bare reads keep the example's point on tenancy and on the one calculated permission.

## The workflow

`Helpdesk.Support.Escalation.Workflow`, queue `:escalations`.

```
ticket        read_one Ticket by id, fail_on_not_found?
assess        plain step — reads context.actor and context.tenant itself
raise         create Escalation — any actor may ask
approval      await "decision", timeout 24h — the run parks here
reassign      update Ticket, :reassign — needs :reassign_tickets, with undo
notify        create AuditEntry
```

```elixir
{:ok, workflow} =
  Magma.start(
    Helpdesk.Support.Escalation.Workflow,
    %{ticket_id: ticket.id, reason: "customer waiting three days"},
    actor: %{id: agent.id},
    tenant: org.id
  )
```

`actor:` and `tenant:` appear in that call and nowhere else. No step declares an `actor`
entity, no step takes a tenant argument, and no step threads either through its
arguments.

**One actor throughout.** The person who raises the escalation is the person the run acts
as, start to finish. `:raise` needs no permission; `:reassign` needs
`:reassign_tickets`. That gap is the whole demonstration — the same actor, the same run,
authorized differently on either side of the park, because the permission is recalculated
rather than replayed.

- An agent raises, is granted `:reassign_tickets` during the park, and `:reassign`
  succeeds on the resuming attempt.
- An agent raises, is granted nothing, and `:reassign` is `Ash.Error.Forbidden` — the run
  fails and unwinds.

`:reassign` implements `undo/4`, restoring the previous assignee, so a rejected decision
puts the ticket back. That rollback authorizes as the same rehydrated actor, from the same
tenant.

`:assess` is a plain `step` with no Ash entity at all. It pattern-matches `context.actor`
and `context.tenant` to decide the escalation's priority — how a non-Ash step reaches the
same two values.

## The magma change

`Magma.Unwind` builds its context by hand (`lib/magma/unwind.ex:39`) and never runs the
reactor's middleware. A rollback would therefore authorize against the bare identity map,
with `permissions` unloaded, and any policy referencing it would raise.

Magma changes so that unwinding runs each middleware's `init/1` over its context before
driving any `undo/4`, matching what `Magma.Run` gets from `Reactor.run/4`. A middleware
returning an error fails the rollback rather than proceeding with an unprepared context.
This is a magma fix in its own right — the rollback path should see the context the
forward path saw — and it needs a test in magma's own suite, not only in the example.

## The console

LiveView on `http://localhost:4000`, over the same store the engine writes.

| Route | |
|---|---|
| `/` | organisation and user switchers, the current tenant's tickets, a form to raise an escalation, a grant / revoke control on each user, and a panel showing what a second organisation sees at the same moment |
| `/escalations/:id` | the tape, the identity and tenant the run carries, the permissions that identity resolves to right now, and approve / reject buttons |

The switchers set the session's actor and tenant; every query the console makes passes
them, so the page itself is subject to the same policies as the workflow. Approve and
reject are one call to `Magma.signal/3`.

Granting `:reassign_tickets` while a run is parked is how the rule is seen by hand: the
row still holds the same identity, and the escalation page's permission list changes
under it. Approving then gets through a step that would have been refused a moment before.

The magma store resources are left as installed — one global table of workflows for every
organisation. The console lists a tenant's runs by filtering on the tenant recorded on the
row.

## Tests

Behaviour, in the payouts example's style.

```
runs every step as the actor and tenant the caller named
keeps the actor and tenant across a park and a later attempt
cannot read a ticket belonging to another organisation
lets a permission granted during the park through
refuses to reassign for an actor holding no grant, and unwinds
puts the assignee back when the decision is a rejection
revokes authority mid-run when a grant is taken away
records an audit entry naming the actor
names the actor and tenant only at the call site
produces the tape the lifecycle describes
```

The last is `tape/1` from `Magma.Testing`. The isolation test starts a workflow for one
organisation against a ticket created in another and asserts the run fails at `:ticket`.
In magma's own suite, one test asserts a middleware's `init/1` runs before any `undo/4`
during unwinding.

## Layout

```
examples/helpdesk/
  lib/helpdesk/
    application.ex  repo.ex
    accounts.ex
    accounts/            organisation.ex  user.ex  grant.ex  role.ex
                         rehydrate.ex  calculations/permissions.ex
    support.ex
    support/             ticket.ex  escalation.ex  audit_entry.ex
                         ticket_status.ex  decision.ex
                         escalation/workflow.ex  escalation/steps.ex
    magma/               generated store resources
  lib/helpdesk_web/      endpoint.ex  router.ex  layouts.ex
                         live/console_live.ex  live/escalation_live.ex
  test/helpdesk/         escalation_test.exs  isolation_test.exs
                         authority_test.exs
  test/helpdesk_web/     console_test.exs
  README.md
```

Deps and aliases mirror `examples/payouts/mix.exs`: `{:magma, path: "../.."}`,
`ash_postgres`, `oban`, `phoenix`, `phoenix_live_view`, `bandit`, `lazy_html` for tests.
`mix setup` creates and migrates; `mix test` migrates first.

The magma store resources come from `mix igniter.install magma`, as a real application
would get them.

## Milestones

1. **Unwind runs middleware** — the magma change and its test, in magma's own suite.
2. **Project skeleton** — mix project, repo, config, application, magma install, migrations.
3. **Domain** — the six resources with their tenancy, the permissions calculation, the
   policies, and seeds.
4. **Rehydration** — the middleware, and the test that a step sees a loaded actor.
5. **Workflow** — the six steps, the undo on `:reassign`, and `escalation_test.exs`.
6. **Authority and isolation** — the grant-during-park test, the forbidden test, the
   revoked test, the cross-tenant test.
7. **Console** — the two LiveViews and `console_test.exs`.
8. **README** — the tour, the table of claims, and the persist-identity rule.
