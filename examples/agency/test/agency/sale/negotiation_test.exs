defmodule Agency.Sale.NegotiationTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.Negotiation

  setup do
    attempt = a_listing(:treaty)
    buyer = a_buyer(attempt, "Jordan Lee")
    offer = an_offer(attempt, buyer, 880_000_00)

    %{attempt: attempt, buyer: buyer, offer: offer}
  end

  defp negotiate(offer) do
    {:ok, workflow} = Magma.start(Negotiation, %{offer_id: offer.id}, queue: :sales)
    run_workflows(queue: :sales)

    workflow
  end

  defp respond(workflow_id, payload) do
    {:ok, _signal} = Magma.signal(workflow_id, "negotiation.response", payload)
    run_workflows(queue: :sales)
  end

  test "a vendor who takes the offer as it stands returns those terms", context do
    %{buyer: buyer, offer: offer} = context

    workflow = negotiate(offer)

    assert status(workflow) == :waiting

    respond(workflow.id, %{decision: :accept})

    assert status(workflow) == :completed

    assert recorded(workflow, :outcome) == %{
             outcome: :accepted,
             buyer_id: buyer.id,
             offer_id: offer.id,
             price: 880_000_00
           }

    assert Sale.get_offer!(offer.id).status == :accepted
  end

  test "each counter opens a fresh round against an offer that supersedes the last", context do
    %{buyer: buyer, offer: offer} = context

    workflow = negotiate(offer)

    respond(workflow.id, %{decision: :counter, amount: 900_000_00})

    second_round = Magma.child_id(workflow.id, :next_round)
    assert status(second_round) == :waiting

    respond(second_round, %{decision: :counter, amount: 920_000_00})

    third_round = Magma.child_id(second_round, :next_round)
    assert status(third_round) == :waiting

    respond(third_round, %{decision: :accept})

    assert length(Enum.uniq([workflow.id, second_round, third_round])) == 3
    assert status(second_round) == :completed
    assert status(third_round) == :completed
    assert status(workflow) == :completed

    [opening, first_counter, second_counter] = Enum.sort_by(Sale.list_offers!(), & &1.id)

    assert opening.id == offer.id
    assert first_counter.supersedes_id == opening.id
    assert second_counter.supersedes_id == first_counter.id
    assert second_counter.amount == 920_000_00

    assert recorded(workflow, :outcome) == %{
             outcome: :accepted,
             buyer_id: buyer.id,
             offer_id: second_counter.id,
             price: 920_000_00
           }
  end

  test "a counter chain that has already run answers a replay without making more offers",
       context do
    %{offer: offer} = context

    workflow = negotiate(offer)
    respond(workflow.id, %{decision: :counter, amount: 900_000_00})
    second_round = Magma.child_id(workflow.id, :next_round)
    respond(second_round, %{decision: :accept})

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => second_round}})
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert length(Sale.list_offers!()) == 2

    assert Enum.map(Enum.sort_by(Sale.list_offers!(), & &1.id), & &1.status) ==
             [:superseded, :accepted]
  end

  test "a buyer who pulls out ends the negotiation without terms", context do
    %{offer: offer} = context

    workflow = negotiate(offer)

    respond(workflow.id, %{decision: :withdraw})

    assert status(workflow) == :completed
    assert recorded(workflow, :outcome) == %{outcome: :no_sale, reason: :withdrawn}
    assert Sale.get_offer!(offer.id).status == :withdrawn
  end

  test "an offer nobody answers before it expires lapses", context do
    %{attempt: attempt, buyer: buyer} = context

    offer =
      an_offer_expiring_at(
        attempt,
        buyer,
        880_000_00,
        DateTime.add(DateTime.utc_now(), 2, :second)
      )

    workflow = negotiate(offer)

    assert status(workflow) == :waiting

    run_agency_after(2_000)

    assert status(workflow) == :completed
    assert recorded(workflow, :outcome) == %{outcome: :no_sale, reason: :lapsed}
    assert Sale.get_offer!(offer.id).status == :lapsed
  end

  test "an offer whose expiry has already passed when nobody has answered lapses", context do
    %{attempt: attempt, buyer: buyer} = context

    expired_offer =
      an_offer_expiring_at(
        attempt,
        buyer,
        880_000_00,
        DateTime.add(DateTime.utc_now(), -5, :second)
      )

    workflow = negotiate(expired_offer)

    assert status(workflow) == :completed
    assert recorded(workflow, :outcome) == %{outcome: :no_sale, reason: :lapsed}
    assert Sale.get_offer!(expired_offer.id).status == :lapsed
  end
end
