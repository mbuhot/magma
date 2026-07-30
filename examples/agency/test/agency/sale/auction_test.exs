defmodule Agency.Sale.AuctionTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.Auction

  @reserve 900_000_00

  setup do
    %{attempt: a_listing(:auction)}
  end

  defp run_auction(attempt) do
    {:ok, workflow} =
      Magma.start(Auction, %{sale_attempt_id: attempt.id, reserve: @reserve}, queue: :sales)

    run_workflows(queue: :sales)

    workflow
  end

  defp fall_hammer(workflow, payload) do
    {:ok, _signal} = Magma.signal(workflow.id, "auction.hammer", payload)
    run_workflows(queue: :sales)
  end

  test "an auction that sells on the day returns the winning bid's terms", %{attempt: attempt} do
    buyer = a_buyer(attempt, "Jordan Lee")
    offer = an_offer(attempt, buyer, 950_000_00)

    workflow = run_auction(attempt)

    assert status(workflow) == :waiting
    assert recorded(workflow, :reserve_set) == %{sale_attempt_id: attempt.id, reserve: @reserve}

    fall_hammer(workflow, %{
      result: :sold,
      buyer_id: buyer.id,
      offer_id: offer.id,
      price: 950_000_00
    })

    assert status(workflow) == :completed

    assert recorded(workflow, :outcome) == %{
             outcome: :accepted,
             buyer_id: buyer.id,
             offer_id: offer.id,
             price: 950_000_00,
             via: :hammer
           }
  end

  test "an auction that passes in sells to the highest bidder by private treaty", %{
    attempt: attempt
  } do
    underbidder = a_buyer(attempt, "Alex Moreau")
    an_offer(attempt, underbidder, 860_000_00)

    highest_bidder = a_buyer(attempt, "Jordan Lee")
    top_bid = an_offer(attempt, highest_bidder, 880_000_00)

    workflow = run_auction(attempt)
    fall_hammer(workflow, %{result: :passed_in})

    negotiation = Magma.child_id(Magma.child_id(workflow.id, :treaty), :negotiation)
    assert status(negotiation) == :waiting

    {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :accept})
    run_workflows(queue: :sales)

    assert status(workflow) == :completed

    assert recorded(workflow, :outcome) == %{
             outcome: :accepted,
             buyer_id: highest_bidder.id,
             offer_id: top_bid.id,
             price: 880_000_00,
             via: :treaty_after_pass_in
           }

    assert Sale.get_offer!(top_bid.id).status == :accepted
  end

  test "an auction that passes in with nobody bidding ends unsold", %{attempt: attempt} do
    workflow = run_auction(attempt)

    fall_hammer(workflow, %{result: :passed_in})

    assert status(workflow) == :completed
    assert recorded(workflow, :outcome) == %{outcome: :no_sale, reason: :passed_in_unsold}
  end

  test "an auction that already sold by treaty answers a replay without selling again", %{
    attempt: attempt
  } do
    highest_bidder = a_buyer(attempt, "Jordan Lee")
    top_bid = an_offer(attempt, highest_bidder, 880_000_00)

    workflow = run_auction(attempt)
    fall_hammer(workflow, %{result: :passed_in})

    negotiation = Magma.child_id(Magma.child_id(workflow.id, :treaty), :negotiation)
    {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :accept})
    run_workflows(queue: :sales)

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => negotiation}})
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert length(Sale.list_offers!()) == 1
    assert Sale.get_offer!(top_bid.id).status == :accepted
  end
end
