defmodule Agency.Sale.AttemptTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.Attempt
  alias Agency.Sale.Jurisdiction
  alias Agency.Sale.Window

  @vic_cooling_off Window.cooling_off(Jurisdiction.cooling_off(:vic).business_days)

  defp start_attempt(attempt) do
    {:ok, workflow} = Magma.start(Attempt, %{sale_attempt_id: attempt.id}, queue: :sales)
    run_agency()

    workflow
  end

  defp accept_by_treaty(workflow) do
    negotiation = Magma.child_id(Magma.child_id(workflow.id, :treaty), :negotiation)
    {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :accept})
    run_agency()
  end

  defp let_cooling_off_lapse, do: run_agency_after(@vic_cooling_off)

  defp answer_the_conditions(workflow, finance) do
    conditions = Magma.child_id(workflow.id, :conditions)

    {:ok, _inspection} =
      Magma.signal(conditions, "condition.inspection", %{decision: :satisfied})

    {:ok, _title} = Magma.signal(conditions, "condition.title", %{decision: :satisfied})
    {:ok, _finance} = Magma.signal(conditions, "condition.finance", %{decision: finance})
    run_agency()

    conditions
  end

  defp report_settlement(workflow, result) do
    {:ok, _signal} = Magma.signal(workflow.id, "settlement.completed", %{result: result})
    run_agency()
  end

  defp the_commission, do: Sale.list_commissions!() |> List.first()
  defp the_deposit, do: Sale.list_deposits!() |> List.first()
  defp the_contract, do: Sale.list_contracts!() |> List.first()

  defp reload(attempt), do: Sale.get_attempt!(attempt.id)

  defp result(workflow) do
    {:ok, reloaded} = Magma.fetch(workflow.id)
    reloaded.result
  end

  describe "a property sold at auction" do
    test "is under no cooling-off right, so its conditions start the moment it exchanges" do
      attempt = a_listing(:auction)
      buyer = a_buyer(attempt, "Jordan Lee")
      offer = an_offer(attempt, buyer, 950_000_00)

      workflow = start_attempt(attempt)

      {:ok, _signal} =
        Magma.signal(Magma.child_id(workflow.id, :auction), "auction.hammer", %{
          result: :sold,
          buyer_id: buyer.id,
          offer_id: offer.id,
          price: 950_000_00
        })

      run_agency()

      assert recorded(workflow, :rescission) == :none
      assert status(Magma.child_id(workflow.id, :conditions)) == :waiting

      assert the_contract().price == 950_000_00
      assert the_deposit().amount == 95_000_00
      assert the_commission().amount == 20_900_00

      assert Sale.list_conditions!() |> Enum.map(& &1.kind) |> Enum.sort() == [
               :finance,
               :inspection,
               :title
             ]
    end
  end

  describe "a property that passes in at auction and sells afterwards by negotiation" do
    test "carries the cooling-off right the state gives a buyer who did not bid at auction" do
      attempt = a_listing(:auction)
      underbidder = a_buyer(attempt, "Alex Moreau")
      an_offer(attempt, underbidder, 860_000_00)
      highest_bidder = a_buyer(attempt, "Jordan Lee")
      top_bid = an_offer(attempt, highest_bidder, 880_000_00)

      workflow = start_attempt(attempt)

      {:ok, _signal} =
        Magma.signal(Magma.child_id(workflow.id, :auction), "auction.hammer", %{
          result: :passed_in
        })

      run_agency()

      negotiation =
        workflow.id
        |> Magma.child_id(:auction)
        |> Magma.child_id(:treaty)
        |> Magma.child_id(:negotiation)

      {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :accept})
      run_agency()

      assert recorded(workflow, :sale).governing_window == :vic
      assert the_contract().price == top_bid.amount

      let_cooling_off_lapse()

      assert recorded(workflow, :rescission) == :timeout
      assert status(Magma.child_id(workflow.id, :conditions)) == :waiting
    end
  end

  describe "a listing whose commission is payable on the contract going unconditional" do
    test "pays the agent out of trust while settlement is still to come" do
      agreement = a_signed_listing(%{sale_method: :treaty, commission_trigger: :on_unconditional})
      attempt = the_first_attempt(agreement, :treaty)
      an_offer(attempt, a_buyer(agreement, "Jordan Lee"), 900_000_00)

      workflow = start_attempt(attempt)
      accept_by_treaty(workflow)
      let_cooling_off_lapse()
      answer_the_conditions(workflow, :approved)

      awaiting_settlement = the_commission()

      assert awaiting_settlement.outcome == :disbursed
      assert awaiting_settlement.paid_from == "Sam Okafor Trust"

      report_settlement(workflow, :settled)

      settled_at = recorded(workflow, :settle).settled_at

      assert DateTime.compare(awaiting_settlement.disbursed_at, settled_at) in [:lt, :eq]
      assert reload(attempt).outcome == :settled
    end
  end

  describe "a listing whose commission is payable on settlement" do
    test "leaves the agent's entitlement accrued until the money moves" do
      agreement = a_signed_listing(%{sale_method: :treaty, commission_trigger: :on_settlement})
      attempt = the_first_attempt(agreement, :treaty)
      an_offer(attempt, a_buyer(agreement, "Jordan Lee"), 900_000_00)

      workflow = start_attempt(attempt)
      accept_by_treaty(workflow)
      let_cooling_off_lapse()
      answer_the_conditions(workflow, :approved)

      assert the_commission().outcome == :accrued

      report_settlement(workflow, :settled)

      settled = the_commission()
      settled_at = recorded(workflow, :settle).settled_at

      assert settled.outcome == :disbursed
      assert settled.disbursed_at == settled_at
      assert the_deposit().status == :released
      assert reload(attempt).outcome == :settled
      assert result(workflow) == %{outcome: :settled, contract_id: the_contract().id}
    end
  end

  describe "a buyer who rescinds during cooling off" do
    test "forfeits two tenths of a percent to the vendor and the underbidder is approached again" do
      agreement = a_signed_listing(%{sale_method: :treaty})
      attempt = the_first_attempt(agreement, :treaty)
      underbidder = a_buyer(agreement, "Alex Moreau")
      an_offer(attempt, underbidder, 860_000_00)
      rescinding_buyer = a_buyer(agreement, "Jordan Lee")
      an_offer(attempt, rescinding_buyer, 900_000_00)

      workflow = start_attempt(attempt)
      accept_by_treaty(workflow)

      {:ok, _signal} =
        Magma.signal(workflow.id, "cooling_off.rescission", %{buyer_id: rescinding_buyer.id})

      run_agency()

      assert recorded(workflow, :rescind) == %{
               forfeited: 1_800_00,
               refunded: 88_200_00,
               forfeited_to: "Priya Nair"
             }

      assert the_deposit().status == :forfeited
      assert the_deposit().forfeited_to == "Priya Nair"
      assert the_deposit().forfeited_amount == 1_800_00
      assert the_commission().outcome == :written_back
      assert reload(attempt).outcome == :rescinded

      successor = the_attempt(agreement, 2)

      assert successor.predecessor_id == attempt.id
      assert successor.sale_method == :treaty

      assert successor.id
             |> Sale.live_offers_for_attempt!()
             |> Enum.map(& &1.buyer_id) == [underbidder.id]

      assert Sale.list_buyers!()
             |> Enum.find(&(&1.id == rescinding_buyer.id))
             |> Map.fetch!(:register_status) == :rescinded

      second_generation = Magma.child_id(workflow.id, :next_attempt)

      assert second_generation != workflow.id
      assert status(second_generation) == :waiting
    end
  end

  describe "a contract whose finance is declined" do
    test "sends the deposit back in full and the campaign resumes against the underbidder" do
      agreement = a_signed_listing(%{sale_method: :treaty})
      attempt = the_first_attempt(agreement, :treaty)
      underbidder = a_buyer(agreement, "Alex Moreau")
      an_offer(attempt, underbidder, 860_000_00)
      declined_buyer = a_buyer(agreement, "Jordan Lee")
      an_offer(attempt, declined_buyer, 900_000_00)

      workflow = start_attempt(attempt)
      accept_by_treaty(workflow)
      let_cooling_off_lapse()
      answer_the_conditions(workflow, :declined)

      assert the_deposit().status == :refunded
      assert the_deposit().amount == 90_000_00
      assert the_commission().outcome == :written_back
      assert reload(attempt).outcome == :condition_failed

      assert Sale.list_conditions!()
             |> Enum.find(&(&1.kind == :finance))
             |> Map.fetch!(:status) == :failed

      successor = the_attempt(agreement, 2)

      assert successor.generation == 2

      assert successor.id
             |> Sale.live_offers_for_attempt!()
             |> Enum.map(& &1.buyer_id) == [underbidder.id]
    end
  end

  describe "a buyer who defaults at settlement" do
    test "still earns the agent their commission, paid out of the deposit they forfeited" do
      agreement = a_signed_listing(%{sale_method: :treaty})
      attempt = the_first_attempt(agreement, :treaty)
      defaulting_buyer = a_buyer(agreement, "Jordan Lee")
      an_offer(attempt, defaulting_buyer, 900_000_00)

      workflow = start_attempt(attempt)
      accept_by_treaty(workflow)
      let_cooling_off_lapse()
      answer_the_conditions(workflow, :approved)
      report_settlement(workflow, :buyer_default)

      commission = the_commission()

      assert commission.outcome == :disbursed
      assert commission.paid_from == "forfeited deposit"
      assert commission.amount == 19_800_00

      assert the_deposit().status == :forfeited
      assert the_deposit().forfeited_to == "Priya Nair"
      assert the_deposit().forfeited_amount == 90_000_00

      assert recorded(workflow, :buyer_default) == %{
               forfeited: 90_000_00,
               to_vendor: 70_200_00
             }

      assert reload(attempt).outcome == :buyer_default

      assert Sale.list_buyers!()
             |> Enum.find(&(&1.id == defaulting_buyer.id))
             |> Map.fetch!(:register_status) == :defaulted
    end
  end

  describe "a campaign that runs out of buyers" do
    test "ends with the register exhausted once the last underbidder pulls out" do
      agreement = a_signed_listing(%{sale_method: :treaty})
      attempt = the_first_attempt(agreement, :treaty)
      underbidder = a_buyer(agreement, "Alex Moreau")
      an_offer(attempt, underbidder, 860_000_00)
      rescinding_buyer = a_buyer(agreement, "Jordan Lee")
      an_offer(attempt, rescinding_buyer, 900_000_00)

      workflow = start_attempt(attempt)
      accept_by_treaty(workflow)

      {:ok, _signal} =
        Magma.signal(workflow.id, "cooling_off.rescission", %{buyer_id: rescinding_buyer.id})

      run_agency()

      second_generation = Magma.child_id(workflow.id, :next_attempt)
      negotiation = Magma.child_id(Magma.child_id(second_generation, :treaty), :negotiation)

      {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :withdraw})
      run_agency()

      assert status(workflow) == :completed
      assert result(workflow) == %{outcome: :no_sale, reason: :register_exhausted}
      assert the_attempt(agreement, 2).outcome == :no_offers
      assert the_attempt(agreement, 3) == nil
    end
  end

  describe "a settled sale that is replayed" do
    test "keeps its one contract and pays its commission once" do
      agreement = a_signed_listing(%{sale_method: :treaty})
      attempt = the_first_attempt(agreement, :treaty)
      an_offer(attempt, a_buyer(agreement, "Jordan Lee"), 900_000_00)

      workflow = start_attempt(attempt)
      accept_by_treaty(workflow)
      let_cooling_off_lapse()
      conditions = answer_the_conditions(workflow, :approved)
      report_settlement(workflow, :settled)

      disbursed_at = the_commission().disbursed_at

      Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => conditions}})
      Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

      assert length(Sale.list_contracts!()) == 1
      assert length(Sale.list_deposits!()) == 1
      assert length(Sale.list_commissions!()) == 1
      assert length(Sale.list_conditions!()) == 3
      assert length(Sale.list_attempts!()) == 1
      assert the_commission().disbursed_at == disbursed_at
      assert the_deposit().status == :released
    end
  end

  defp the_first_attempt(agreement, sale_method) do
    Sale.open_attempt!(%{
      agency_agreement_id: agreement.id,
      generation: 1,
      sale_method: sale_method,
      opened_at: ~U[2026-08-05 00:00:00Z]
    })
  end
end
