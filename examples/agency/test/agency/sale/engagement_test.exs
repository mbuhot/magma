defmodule Agency.Sale.EngagementTest do
  use Agency.DataCase, async: false

  alias Agency.Lender
  alias Agency.Pexa
  alias Agency.Sale
  alias Agency.Sale.Engagement
  alias Agency.Sale.Jurisdiction
  alias Agency.Sale.Window
  alias Agency.Titles

  @vic_cooling_off Window.cooling_off(Jurisdiction.cooling_off(:vic).business_days)

  defp engage(agreement) do
    {:ok, workflow} =
      Magma.start(Engagement, %{agency_agreement_id: agreement.id}, queue: :sales)

    run_agency()

    workflow
  end

  defp hand_over_the_vendor_statement(workflow) do
    gate = Magma.child_id(workflow.id, :compliance_gate)

    Enum.each(
      ["document.vendor_statement", "document.statement_of_information", "document.title_search"],
      fn document ->
        {:ok, _signal} = Magma.signal(gate, document, %{})
        run_agency()
      end
    )

    gate
  end

  defp result(workflow) do
    {:ok, reloaded} = Magma.fetch(workflow.id)
    reloaded.result
  end

  test "a listing that clears its documents, sells by set date and settles pays the agent out" do
    agreement = a_signed_listing(%{sale_method: :set_date})
    buyer = a_buyer(agreement, "Jordan Lee")

    workflow = engage(agreement)
    gate = hand_over_the_vendor_statement(workflow)

    assert status(gate) == :completed
    assert recorded(workflow, :campaign).address == "31 Rosebank Avenue"

    {:ok, _signal} = Magma.signal(workflow.id, "campaign.outcome", %{decision: :proceed})
    run_agency()

    attempt = the_attempt(agreement, 1)

    assert attempt.generation == 1
    assert attempt.sale_method == :set_date

    offer = an_offer(attempt, buyer, 940_000_00)

    sale = Magma.child_id(workflow.id, :sale_attempt)
    set_date = Magma.child_id(sale, :set_date)

    {:ok, _signal} = Magma.signal(set_date, "set_date.offers_close", %{})
    run_agency()

    negotiation =
      Magma.child_id(set_date, {Reactor.Step.Map, :negotiations, :negotiation, 0})

    {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :accept})
    run_agency()

    {:ok, _signal} = Magma.signal(set_date, "set_date.vendor_selection", %{offer_id: offer.id})
    run_agency()

    contract = Sale.list_contracts!() |> List.first()

    assert contract.price == 940_000_00
    assert contract.buyer_id == buyer.id
    assert Sale.list_deposits!() |> List.first() |> Map.fetch!(:amount) == 94_000_00

    run_agency_after(@vic_cooling_off)

    assert recorded(sale, :rescission) == :timeout

    conditions = Magma.child_id(sale, :conditions)
    contract_id = Sale.list_contracts!() |> List.first() |> Map.fetch!(:id)

    {:ok, _inspection} =
      Magma.signal(conditions, "condition.inspection", %{decision: :satisfied})

    Lender.move!(contract_id, :approved)
    Titles.move!(contract_id, :clear)
    nudge(conditions)

    assert Sale.list_contracts!() |> List.first() |> Map.fetch!(:unconditional_at) != nil
    assert Sale.list_conditions!() |> Enum.all?(&(&1.status == :satisfied))

    Pexa.move!(contract_id, :settled)
    nudge(sale)

    commission = Sale.list_commissions!() |> List.first()

    assert commission.amount == 20_680_00
    assert commission.outcome == :disbursed
    assert commission.paid_from == "Sam Okafor Trust"

    assert Sale.list_deposits!() |> List.first() |> Map.fetch!(:status) == :released
    assert Sale.get_attempt!(attempt.id).outcome == :settled
    assert status(workflow) == :completed
    assert result(workflow) == %{outcome: :settled, contract_id: contract.id}
  end

  test "a listing whose agreement runs out mid campaign ends with the term expired" do
    agreement = a_signed_listing(%{sale_method: :treaty})

    workflow = engage(agreement)
    hand_over_the_vendor_statement(workflow)

    assert status(workflow) == :waiting

    run_agency_after(Window.agency_term())

    assert status(workflow) == :completed
    assert result(workflow) == %{outcome: :expired}
    assert Sale.list_attempts!() == []
  end

  test "a vendor who pulls the listing before any offer ends the engagement withdrawn" do
    agreement = a_signed_listing(%{sale_method: :treaty})

    workflow = engage(agreement)
    hand_over_the_vendor_statement(workflow)

    {:ok, _signal} = Magma.signal(workflow.id, "campaign.outcome", %{decision: :withdrawn})
    run_agency()

    assert status(workflow) == :completed
    assert result(workflow) == %{outcome: :withdrawn}
    assert Sale.list_attempts!() == []
  end
end
