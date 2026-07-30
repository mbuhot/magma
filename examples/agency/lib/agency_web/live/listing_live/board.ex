defmodule AgencyWeb.ListingLive.Board do
  @moduledoc """
  Everything the sales desk shows for one listing, assembled from the domain's own rows.

  What the listing is presently waiting on is read from those rows first — how many
  compliance documents have arrived, which offers are still live, whether a contract has gone
  unconditional. Only where the rows alone cannot tell two waits apart (an auction not yet
  hammered from one already passed in, a chain of counters against a single offer) does it
  fall back to asking magma what a workflow is parked on, and that answer never reaches the
  template as anything but a plain-language action.
  """

  alias Agency.Lender
  alias Agency.Sale
  alias Agency.Sale.Jurisdiction
  alias Agency.Sale.Ledger
  alias Agency.Sale.Register
  alias Agency.Sale.Runs

  defstruct [
    :agreement,
    :property,
    :buyers,
    :required_documents,
    :received_documents,
    :stage,
    :attempt,
    :offers,
    :contract,
    :conditions,
    :deposit,
    :commission,
    :totals,
    :history,
    :underbidders,
    :feed,
    :workflows
  ]

  @type t :: %__MODULE__{}

  @doc "Cents formatted as dollars, for display at the edge."
  @spec money(integer()) :: String.t()
  def money(cents) do
    dollars = div(round(cents), 100)
    sign = if dollars < 0, do: "-", else: ""

    grouped =
      dollars
      |> abs()
      |> Integer.to_string()
      |> String.reverse()
      |> String.codepoints()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    "#{sign}$#{grouped}"
  end

  @doc "Every listing on the agent's desk, for the picker."
  @spec listings() :: [Ash.Resource.record()]
  def listings do
    Sale.list_agreements!(load: [:property]) |> Enum.sort_by(& &1.property.address)
  end

  @doc "Everything the board needs to show one listing."
  @spec load(String.t()) :: t()
  def load(agency_agreement_id) do
    agreement = Sale.get_agreement!(agency_agreement_id, load: [:property])
    buyers = buyers_for(agency_agreement_id)
    attempts = attempts_for(agency_agreement_id)
    attempt = List.last(attempts)

    contract = attempt && contract_for(attempt.id)
    conditions = (contract && Sale.conditions_for_contract!(contract.id)) || []
    deposit = contract && deposit_for(contract.id)
    commission = attempt && commission_for(attempt.id)
    offers = attempt && Sale.offers_for_attempt!(attempt.id)

    workflows = %{
      engagement_id: Runs.engagement_id(agency_agreement_id),
      campaign_id: Runs.campaign_id(agency_agreement_id),
      attempt_workflow_ids: Runs.attempt_workflow_ids(attempts),
      negotiations: Runs.negotiations_awaiting_response()
    }

    %__MODULE__{
      agreement: agreement,
      property: agreement.property,
      buyers: buyers,
      required_documents: Jurisdiction.required_documents(agreement.property.jurisdiction),
      received_documents: received_documents(agency_agreement_id),
      stage: stage(agreement, attempt, contract, workflows),
      attempt: attempt,
      offers: offers || [],
      contract: contract,
      conditions: conditions,
      deposit: deposit,
      commission: commission,
      totals: totals(commission, deposit, history(attempts)),
      history: history(attempts),
      underbidders: underbidders(agency_agreement_id, attempts),
      feed: feed(agreement, attempts, contract, conditions, commission, deposit),
      workflows: workflows
    }
  end

  defp underbidders(agency_agreement_id, attempts) do
    contracts = Enum.flat_map(attempts, &Sale.contracts_for_attempt!(&1.id))

    agency_agreement_id
    |> Register.approachable()
    |> Enum.map(fn {buyer, offer} ->
      %{buyer: buyer, amount: offer.amount, finance: finance_position(buyer, offer, contracts)}
    end)
    |> Enum.sort_by(& &1.amount, :desc)
  end

  defp finance_position(buyer, offer, contracts) do
    case Enum.find(contracts, &(&1.buyer_id == buyer.id)) do
      nil -> unproven_finance(buyer, offer)
      contract -> lender_position(contract, buyer, offer)
    end
  end

  defp lender_position(contract, buyer, offer) do
    case Lender.status(contract.id) do
      :approved -> :approved
      :declined -> :declined
      _undecided -> unproven_finance(buyer, offer)
    end
  end

  defp unproven_finance(%{lender: lender}, _offer) when lender in [nil, "cash"], do: :cash

  defp unproven_finance(_buyer, offer) do
    if :finance in offer.requested_conditions, do: :subject_to_finance, else: :cash
  end

  defp buyers_for(agency_agreement_id) do
    Sale.list_buyers!()
    |> Enum.filter(&(&1.agency_agreement_id == agency_agreement_id))
    |> Enum.sort_by(& &1.inserted_at)
  end

  defp attempts_for(agency_agreement_id) do
    Sale.attempts_for_agreement!(agency_agreement_id)
  end

  defp contract_for(sale_attempt_id) do
    Sale.contracts_for_attempt!(sale_attempt_id) |> List.first()
  end

  defp deposit_for(contract_id) do
    Sale.deposits_for_contract!(contract_id) |> List.first()
  end

  defp commission_for(sale_attempt_id) do
    Sale.commissions_for_attempt!(sale_attempt_id) |> List.first()
  end

  defp received_documents(agency_agreement_id) do
    Sale.list_compliance_documents!()
    |> Enum.filter(&(&1.agency_agreement_id == agency_agreement_id and &1.received_at))
    |> Enum.map(& &1.kind)
    |> MapSet.new()
  end

  defp stage(agreement, attempt, contract, workflows) do
    required = Jurisdiction.required_documents(agreement.property.jurisdiction)
    received = received_documents(agreement.id)

    cond do
      Enum.any?(required, &(&1 not in received)) -> :prep
      is_nil(attempt) and is_nil(workflows.campaign_id) -> :prep
      is_nil(attempt) -> :marketing
      attempt.outcome == :settled -> :settled
      attempt.outcome != :running -> closed_stage(attempt, workflows)
      is_nil(contract) -> running_stage(attempt, workflows)
      is_nil(contract.unconditional_at) -> post_exchange_stage(attempt, workflows)
      true -> :awaiting_settlement
    end
  end

  defp closed_stage(attempt, workflows) do
    attempt_workflow_id = Map.get(workflows.attempt_workflow_ids, attempt.id)

    cond do
      attempt_workflow_id && Runs.waiting_on?(attempt_workflow_id, "succession.decision") ->
        :back_on_market

      workflows.campaign_id ->
        :marketing

      true ->
        :lapsed
    end
  end

  defp post_exchange_stage(attempt, workflows) do
    attempt_workflow_id = Map.get(workflows.attempt_workflow_ids, attempt.id)

    if attempt_workflow_id && Runs.waiting_on?(attempt_workflow_id, "cooling_off.rescission") do
      :cooling
    else
      :conditions
    end
  end

  defp running_stage(%{sale_method: :auction} = attempt, workflows) do
    attempt_workflow_id = Map.get(workflows.attempt_workflow_ids, attempt.id)

    auction_id =
      attempt_workflow_id && Runs.method_workflow_id(attempt_workflow_id, :auction)

    if auction_id && Runs.waiting_on?(auction_id, "auction.hammer") do
      :auction_day
    else
      :negotiating
    end
  end

  defp running_stage(%{sale_method: :set_date} = attempt, workflows) do
    attempt_workflow_id = Map.get(workflows.attempt_workflow_ids, attempt.id)

    set_date_id =
      attempt_workflow_id && Runs.method_workflow_id(attempt_workflow_id, :set_date)

    cond do
      set_date_id && Runs.waiting_on?(set_date_id, "set_date.offers_close") ->
        :offers_open

      set_date_id && Runs.waiting_on?(set_date_id, "set_date.vendor_selection") ->
        :negotiating

      true ->
        :offers_in
    end
  end

  defp running_stage(%{sale_method: :treaty}, _workflows), do: :negotiating

  defp totals(commission, deposit, history) do
    commissions = [commission | Enum.map(history, & &1.commission)] |> Enum.reject(&is_nil/1)
    deposits = [deposit | Enum.map(history, & &1.deposit)] |> Enum.reject(&is_nil/1)

    Ledger.totals(commissions, deposits)
  end

  defp history(attempts) do
    attempts
    |> Enum.filter(&(&1.outcome in [:rescinded, :condition_failed, :buyer_default]))
    |> Enum.sort_by(& &1.generation, :desc)
    |> Enum.map(fn attempt ->
      contract = contract_for(attempt.id)
      deposit = contract && deposit_for(contract.id)
      commission = commission_for(attempt.id)
      buyer = contract && Sale.get_buyer!(contract.buyer_id)

      %{
        attempt: attempt,
        contract: contract,
        deposit: deposit,
        commission: commission,
        buyer: buyer,
        reason: reason(attempt.outcome)
      }
    end)
  end

  defp reason(:rescinded), do: "Rescinded during cooling off"
  defp reason(:condition_failed), do: "A condition was not satisfied"
  defp reason(:buyer_default), do: "Defaulted at settlement"

  defp feed(agreement, attempts, contract, conditions, commission, deposit) do
    document_events =
      Sale.list_compliance_documents!()
      |> Enum.filter(&(&1.agency_agreement_id == agreement.id and &1.received_at))
      |> Enum.map(&{&1.received_at, "Received the #{document_label(&1.kind)}"})

    contract_events =
      if contract do
        buyer = Sale.get_buyer!(contract.buyer_id)

        exchanged = [
          {contract.exchanged_at,
           "Exchanged contracts with #{buyer.name} at #{money(contract.price)}"}
        ]

        unconditional =
          if contract.unconditional_at,
            do: [{contract.unconditional_at, "The contract went unconditional"}],
            else: []

        exchanged ++ unconditional
      else
        []
      end

    condition_events =
      conditions
      |> Enum.filter(&(&1.status != :pending))
      |> Enum.map(&{&1.updated_at, condition_text(&1)})

    commission_events =
      if commission && commission.disbursed_at,
        do: [{commission.disbursed_at, "Commission of #{money(commission.amount)} paid"}],
        else: []

    deposit_events =
      case deposit do
        %{status: :forfeited, forfeited_amount: amount, forfeited_to: to} ->
          [{deposit.updated_at, "#{money(amount)} of the deposit forfeited to #{to}"}]

        %{status: :refunded} ->
          [{deposit.updated_at, "The deposit was refunded in full"}]

        _otherwise ->
          []
      end

    history_events =
      attempts
      |> Enum.filter(&(&1.outcome in [:rescinded, :condition_failed, :buyer_default]))
      |> Enum.map(&{&1.closed_at, "Generation #{&1.generation} closed: #{reason(&1.outcome)}"})

    (document_events ++
       contract_events ++
       condition_events ++ commission_events ++ deposit_events ++ history_events)
    |> Enum.sort_by(&elem(&1, 0), {:desc, DateTime})
  end

  defp document_label(:contract), do: "contract of sale"
  defp document_label(:title_search), do: "title search"
  defp document_label(:drainage_diagram), do: "drainage diagram"
  defp document_label(:planning_certificate), do: "planning certificate"
  defp document_label(:vendor_statement), do: "vendor statement"
  defp document_label(:statement_of_information), do: "statement of information"
  defp document_label(:form_6), do: "Form 6 appointment"
  defp document_label(:seller_disclosure), do: "seller disclosure statement"

  defp condition_text(%{kind: kind, status: :satisfied}), do: "#{condition_label(kind)} satisfied"
  defp condition_text(%{kind: kind, status: :failed}), do: "#{condition_label(kind)} failed"

  defp condition_label(:finance), do: "Finance"
  defp condition_label(:inspection), do: "Building and pest"
  defp condition_label(:title), do: "Title search"
end
