defmodule Helpdesk.Support.Escalation.Workflow do
  @moduledoc """
  An escalation, end to end, run as the person who asked for it.

  `Magma.start/3` is told an actor and a tenant once. Nothing below names either again: no
  step declares an `actor`, none takes a tenant argument, and none threads either through its
  arguments. `Ash.Reactor` reads both off the reactor context, and magma seeds that context
  from the workflow's row on every attempt.

  The run acts as the person who asked, which is what reads the ticket and records the
  request. Moving the ticket is somebody else's authority, so `:reassign` names the person who
  decided as its actor — the one place either is stated per step, and only because the domain
  says so.

  Whether that decider may act is read when the run wakes, not when it parked. An agent given
  cover while their request sat waiting can approve it themselves.

  | | |
  |---|---|
  | The run acts as its caller | the actor is on the context, from the row, on every attempt |
  | Another organisation's ticket is not found | tenancy scopes `:ticket`, and it fails on not found |
  | A decision carries its own authority | `:reassign` takes its actor from `:decider` |
  | Authority is current, not frozen | `:decider` is read on the attempt that wakes |
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

  read_one :decider, Helpdesk.Accounts.User, :by_id do
    inputs(%{id: result(:approval, [:decided_by_id])})
    fail_on_not_found?(true)
  end

  update :reassign, Helpdesk.Support.Ticket, :reassign do
    initial(result(:ticket))
    inputs(%{assignee_id: result(:approval, [:assignee_id])})
    actor(result(:decider))
    undo(:always)
    undo_action(:restore_assignee)
  end

  create :notify, Helpdesk.Support.AuditEntry, :record do
    inputs(%{action: value("escalation decided")})
    actor(result(:decider))
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

  @doc """
  The most recent run raised against a ticket, or `nil`.

  The console holds no reference of its own: a run records the ticket it was started for in
  its inputs, so the ticket's page finds it by asking the store.
  """
  @spec latest_for(Ash.Resource.record()) :: Ash.Resource.record() | nil
  def latest_for(%{id: ticket_id, org_id: org_id}) do
    Helpdesk.Magma.Workflow
    |> Ash.read!()
    |> Enum.filter(&(&1.tenant == org_id and raised_for?(&1, ticket_id)))
    |> Enum.max_by(& &1.id, fn -> nil end)
  end

  defp raised_for?(%{inputs: %{ticket_id: ticket_id}}, ticket_id), do: true
  defp raised_for?(_workflow, _ticket_id), do: false

  @doc """
  Tells a parked escalation what was decided, by whom, and who the ticket goes to.

  The decider travels in the signal because it is not known when the run starts. `:reassign`
  names them as its actor, so the move is authorized against the authority of the person who
  approved it, read at the moment the run wakes.
  """
  @spec decide(String.t(), Helpdesk.Support.Decision.t(), String.t(), String.t() | nil) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def decide(workflow_id, decision, decided_by_id, assignee_id \\ nil) do
    Magma.signal(workflow_id, "decision", %{
      decision: decision,
      decided_by_id: decided_by_id,
      assignee_id: assignee_id
    })
  end
end
