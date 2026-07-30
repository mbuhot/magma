defmodule AgencyWeb.ListingLive.Workflows do
  @moduledoc """
  The magma workflow ids behind one listing, and what they are parked on.

  Nothing here is shown to the agent. It exists so the board can tell which signal to send
  and to whom, reading the workflow ids back from the domain rows they were started from
  rather than storing them anywhere new.
  """

  alias Agency.Magma.Waiter
  alias Agency.Magma.Workflow
  alias Agency.Sale.Engagement

  @doc "The engagement workflow running the given agency agreement, if one has been started."
  @spec engagement_id(String.t()) :: String.t() | nil
  def engagement_id(agency_agreement_id) do
    Workflow
    |> Ash.read!()
    |> Enum.find(&engaged?(&1, agency_agreement_id))
    |> case do
      nil -> nil
      workflow -> workflow.id
    end
  end

  defp engaged?(%{module: Engagement, inputs: %{agency_agreement_id: id}}, id), do: true
  defp engaged?(_workflow, _agency_agreement_id), do: false

  @doc "The compliance gate dispatched beneath an engagement."
  @spec compliance_gate_id(String.t()) :: String.t()
  def compliance_gate_id(engagement_id), do: Magma.child_id(engagement_id, :compliance_gate)

  @doc """
  Every sale attempt's workflow id, keyed by the attempt row's own id.

  Each generation's workflow id is derived from its predecessor's, so the whole chain is
  walked from the first attempt forward rather than guessed at.
  """
  @spec attempt_workflow_ids(String.t(), [Ash.Resource.record()]) :: %{String.t() => String.t()}
  def attempt_workflow_ids(engagement_id, attempts_by_generation) do
    {pairs, _next} =
      attempts_by_generation
      |> Enum.sort_by(& &1.generation)
      |> Enum.map_reduce(Magma.child_id(engagement_id, :sale_attempt), fn attempt, id ->
        {{attempt.id, id}, Magma.child_id(id, :next_attempt)}
      end)

    Map.new(pairs)
  end

  @doc "The child workflow that runs an attempt's sale method."
  @spec method_workflow_id(String.t(), atom()) :: String.t()
  def method_workflow_id(attempt_workflow_id, :auction),
    do: Magma.child_id(attempt_workflow_id, :auction)

  def method_workflow_id(attempt_workflow_id, :set_date),
    do: Magma.child_id(attempt_workflow_id, :set_date)

  def method_workflow_id(attempt_workflow_id, :treaty),
    do: Magma.child_id(attempt_workflow_id, :treaty)

  @doc "The conditions workflow dispatched once a contract exchanges."
  @spec conditions_id(String.t()) :: String.t()
  def conditions_id(attempt_workflow_id), do: Magma.child_id(attempt_workflow_id, :conditions)

  @doc "The child a private treaty dispatches to negotiate its one offer."
  @spec negotiation_of_treaty(String.t()) :: String.t()
  def negotiation_of_treaty(treaty_workflow_id),
    do: Magma.child_id(treaty_workflow_id, :negotiation)

  @doc "Whether a workflow is currently parked on the given signal name."
  @spec waiting_on?(String.t(), String.t()) :: boolean()
  def waiting_on?(workflow_id, name) do
    Waiter
    |> Ash.read!()
    |> Enum.any?(&(&1.workflow_id == workflow_id and &1.name == name))
  end

  @doc """
  Every offer currently awaiting a response, mapped to the negotiation workflow parked on it.

  A negotiation is its own workflow per round of a chain, so the round presently parked is
  found by what it is waiting on rather than by retracing how many times it has been
  countered.
  """
  @spec negotiations_awaiting_response() :: %{String.t() => String.t()}
  def negotiations_awaiting_response do
    workflows_by_id = Workflow |> Ash.read!() |> Map.new(&{&1.id, &1})

    Waiter
    |> Ash.read!()
    |> Enum.filter(&(&1.name == "negotiation.response"))
    |> Enum.flat_map(fn waiter ->
      case Map.get(workflows_by_id, waiter.workflow_id) do
        %{inputs: %{offer_id: offer_id}} -> [{offer_id, waiter.workflow_id}]
        _otherwise -> []
      end
    end)
    |> Map.new()
  end
end
