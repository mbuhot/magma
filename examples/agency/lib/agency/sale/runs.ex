defmodule Agency.Sale.Runs do
  @moduledoc """
  The magma workflow ids behind one listing, and what they are parked on.

  Nothing here is shown to the agent. It exists so the board can tell which signal to send
  and to whom, reading the workflow ids back from the domain rows they were started from
  rather than storing them anywhere new.
  """

  alias Agency.Magma.Waiter
  alias Agency.Magma.Workflow
  alias Agency.Sale.Attempt
  alias Agency.Sale.Campaign
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
  The campaign presently waiting to be taken to market, if one is.

  A listing is marketed afresh as often as the agent relaunches it, and each of those campaigns
  is its own workflow, so which one holds the vendor's decision is found by what is parked.
  """
  @spec campaign_id(String.t()) :: String.t() | nil
  def campaign_id(agency_agreement_id) do
    campaigns =
      Workflow
      |> Ash.read!()
      |> Enum.filter(&campaigning?(&1, agency_agreement_id))
      |> MapSet.new(& &1.id)

    Waiter
    |> Ash.read!()
    |> Enum.find(&(&1.name == "campaign.outcome" and MapSet.member?(campaigns, &1.workflow_id)))
    |> case do
      nil -> nil
      waiter -> waiter.workflow_id
    end
  end

  defp campaigning?(%{module: Campaign, inputs: %{agency_agreement_id: id}}, id), do: true
  defp campaigning?(_workflow, _agency_agreement_id), do: false

  @doc "Every sale attempt's workflow id, keyed by the attempt row's own id."
  @spec attempt_workflow_ids([Ash.Resource.record()]) :: %{String.t() => String.t()}
  def attempt_workflow_ids(attempts) do
    attempt_ids = MapSet.new(attempts, & &1.id)

    Workflow
    |> Ash.read!()
    |> Enum.flat_map(&attempt_pair(&1, attempt_ids))
    |> Map.new()
  end

  defp attempt_pair(%{module: Attempt, id: workflow_id, inputs: %{sale_attempt_id: id}}, ids) do
    if MapSet.member?(ids, id), do: [{id, workflow_id}], else: []
  end

  defp attempt_pair(_workflow, _attempt_ids), do: []

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

  @doc "The compliance gate behind a listing."
  @spec gate_id(String.t()) :: String.t()
  def gate_id(agency_agreement_id) do
    agency_agreement_id |> engagement_id() |> compliance_gate_id()
  end

  @doc "The workflow running a listing's latest sale attempt."
  @spec attempt_id(String.t()) :: String.t()
  def attempt_id(agency_agreement_id) do
    attempt = agency_agreement_id |> Agency.Sale.attempts_for_agreement!() |> List.last()

    [attempt] |> attempt_workflow_ids() |> Map.fetch!(attempt.id)
  end

  @doc "The workflow running the sale method of a listing's latest attempt."
  @spec method_id(String.t(), atom()) :: String.t()
  def method_id(agency_agreement_id, method) do
    agency_agreement_id |> attempt_id() |> method_workflow_id(method)
  end

  @doc "The conditions workflow of a listing's latest attempt."
  @spec conditions_of(String.t()) :: String.t()
  def conditions_of(agency_agreement_id) do
    agency_agreement_id |> attempt_id() |> conditions_id()
  end

  @doc "The negotiation presently awaiting a response to the given offer."
  @spec negotiation_of_offer(String.t()) :: String.t()
  def negotiation_of_offer(offer_id) do
    negotiations_awaiting_response() |> Map.fetch!(offer_id)
  end
end
