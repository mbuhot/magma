defmodule Helpdesk.Support.Escalation.Workflow do
  @moduledoc """
  An escalation, end to end, run as the person who asked for it.

  `Magma.start/3` is told an actor and a tenant once. Nothing below names either again: no
  step declares an `actor`, none takes a tenant argument, and none threads either through its
  arguments. `Ash.Reactor` reads both off the reactor context, and magma seeds that context
  from the workflow's row on every attempt.

  The demonstration is the gap either side of the wait. Raising needs no permission.
  Reassigning needs `:reassign_tickets`. Same actor, same run — and which way it goes is
  decided by the grants that stand when the run wakes, because `Helpdesk.Accounts.Rehydrate`
  loads the actor's permissions afresh each attempt.

  | | |
  |---|---|
  | The run acts as its caller | the actor is on the context, from the row, on every attempt |
  | Another organisation's ticket is not found | tenancy scopes `:ticket`, and it fails on not found |
  | Authority is current, not frozen | a grant made during the wait lets `:reassign` through |
  | A rejection puts the ticket back | `:outcome` fails, and `:reassign` has an undo |
  """

  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  alias Helpdesk.Support.Escalation.Steps

  magma do
    queue(:escalations)
  end

  middlewares do
    middleware(Helpdesk.Accounts.Rehydrate)
  end

  input(:ticket_id)
  input(:reason)

  read_one :ticket, Helpdesk.Support.Ticket, :by_id do
    inputs(%{id: input(:ticket_id)})
    fail_on_not_found?(true)
  end

  step :assess, Steps.Assess do
    argument(:ticket, result(:ticket))
  end

  create :raise, Helpdesk.Support.Escalation, :raise do
    inputs(%{ticket_id: result(:ticket, [:id]), reason: input(:reason)})
    undo(:always)
    undo_action(:withdraw)
    wait_for(:assess)
  end

  await :approval do
    signal("decision")
    timeout(:timer.hours(24))
    wait_for(:raise)
  end

  update :reassign, Helpdesk.Support.Ticket, :reassign do
    initial(result(:ticket))
    inputs(%{assignee_id: result(:approval, [:assignee_id])})
    undo(:always)
    undo_action(:restore_assignee)
  end

  create :notify, Helpdesk.Support.AuditEntry, :record do
    inputs(%{action: value("escalation decided")})
    wait_for(:reassign)
  end

  step :outcome, Steps.Outcome do
    argument(:ticket, result(:reassign))
    argument(:decision, result(:approval))
    wait_for(:notify)
  end

  return(:outcome)

  @doc "Starts an escalation of a ticket, as the person asking for it."
  @spec start(Ash.Resource.record(), String.t(), Ash.Resource.record()) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def start(ticket, reason, actor) do
    Magma.start(__MODULE__, %{ticket_id: ticket.id, reason: reason},
      actor: %{id: actor.id},
      tenant: ticket.org_id
    )
  end

  @doc "Tells a parked escalation what was decided, and who the ticket goes to."
  @spec decide(String.t(), Helpdesk.Support.Decision.t(), String.t() | nil) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def decide(workflow_id, decision, assignee_id \\ nil) do
    Magma.signal(workflow_id, "decision", %{decision: decision, assignee_id: assignee_id})
  end
end
