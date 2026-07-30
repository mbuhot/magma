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

  defp the_campaign(workflow), do: Magma.child_id(workflow.id, :campaign)

  defp take_it_to_market(campaign) do
    {:ok, _signal} = Magma.signal(campaign, "campaign.outcome", %{decision: :proceed})
    run_agency()
  end

  defp negotiation_of(set_date, index) do
    Magma.child_id(set_date, {Reactor.Step.Map, :negotiations, :negotiation, index})
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
    campaign = the_campaign(workflow)

    assert status(gate) == :completed
    assert recorded(campaign, :launch).address == "31 Rosebank Avenue"

    take_it_to_market(campaign)

    attempt = the_attempt(agreement, 1)

    assert attempt.generation == 1
    assert attempt.sale_method == :set_date

    offer = an_offer(attempt, buyer, 940_000_00)

    sale = Magma.child_id(campaign, :sale_attempt)
    set_date = Magma.child_id(sale, :set_date)

    {:ok, _signal} = Magma.signal(set_date, "set_date.offers_close", %{})
    run_agency()

    {:ok, _signal} =
      Magma.signal(negotiation_of(set_date, 0), "negotiation.response", %{decision: :accept})

    run_agency()

    {:ok, _signal} = Magma.signal(set_date, "set_date.vendor_selection", %{offer_id: offer.id})
    run_agency()

    contract = the_contract(attempt)

    assert contract.price == 940_000_00
    assert contract.buyer_id == buyer.id
    assert the_deposit(attempt).amount == 94_000_00

    run_agency_after(@vic_cooling_off)

    assert recorded(sale, :rescission) == :timeout

    conditions = Magma.child_id(sale, :conditions)

    {:ok, _inspection} =
      Magma.signal(conditions, "condition.inspection", %{decision: :satisfied})

    Lender.move!(contract.id, :approved)
    Titles.move!(contract.id, :clear)
    nudge(conditions)

    assert the_contract(attempt).unconditional_at != nil
    assert attempt |> the_conditions() |> Enum.all?(&(&1.status == :satisfied))

    Pexa.move!(contract.id, :settled)
    nudge(sale)

    commission = the_commission(attempt)

    assert commission.amount == 20_680_00
    assert commission.outcome == :disbursed
    assert commission.paid_from == "Sam Okafor Trust"

    assert the_deposit(attempt).status == :released
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
    assert Sale.attempts_for_agreement!(agreement.id) == []
  end

  test "a vendor who pulls the listing before any offer ends the engagement withdrawn" do
    agreement = a_signed_listing(%{sale_method: :treaty})

    workflow = engage(agreement)
    hand_over_the_vendor_statement(workflow)

    {:ok, _signal} =
      Magma.signal(the_campaign(workflow), "campaign.outcome", %{decision: :withdrawn})

    run_agency()

    assert status(workflow) == :completed
    assert result(workflow) == %{outcome: :withdrawn}
    assert Sale.attempts_for_agreement!(agreement.id) == []
  end

  test "an agent who relaunches after a rescission puts the property back on the market" do
    agreement = a_signed_listing(%{sale_method: :set_date})
    rescinding_buyer = a_buyer(agreement, "Jordan Lee")
    underbidder = a_buyer(agreement, "Alex Moreau")

    workflow = engage(agreement)
    hand_over_the_vendor_statement(workflow)
    campaign = the_campaign(workflow)
    take_it_to_market(campaign)

    first_generation = the_attempt(agreement, 1)
    winning_offer = an_offer(first_generation, rescinding_buyer, 940_000_00)
    an_offer(first_generation, underbidder, 905_000_00)

    sale = Magma.child_id(campaign, :sale_attempt)
    set_date = Magma.child_id(sale, :set_date)

    {:ok, _signal} = Magma.signal(set_date, "set_date.offers_close", %{})
    run_agency()

    Enum.each(0..1, fn index ->
      {:ok, _signal} =
        Magma.signal(negotiation_of(set_date, index), "negotiation.response", %{decision: :accept})

      run_agency()
    end)

    {:ok, _signal} =
      Magma.signal(set_date, "set_date.vendor_selection", %{offer_id: winning_offer.id})

    run_agency()

    {:ok, _signal} =
      Magma.signal(sale, "cooling_off.rescission", %{buyer_id: rescinding_buyer.id})

    run_agency()

    assert Sale.get_attempt!(first_generation.id).outcome == :rescinded

    {:ok, _signal} = Magma.signal(sale, "succession.decision", %{decision: :relaunch})
    run_agency()

    relaunched = Magma.child_id(campaign, :relaunch)

    assert the_attempt(agreement, 2) == nil
    assert waiting?(relaunched, "campaign.outcome")
    assert recorded(relaunched, :launch).address == "31 Rosebank Avenue"

    take_it_to_market(relaunched)

    second_generation = the_attempt(agreement, 2)

    assert second_generation.sale_method == :set_date
    assert second_generation.predecessor_id == first_generation.id
    assert second_generation.outcome == :running
    assert status(workflow) == :waiting
  end
end
