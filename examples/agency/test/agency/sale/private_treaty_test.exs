defmodule Agency.Sale.PrivateTreatyTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.PrivateTreaty

  test "a treaty reports the terms its negotiation reached" do
    attempt = a_listing(:treaty)
    buyer = a_buyer(attempt, "Jordan Lee")
    offer = an_offer(attempt, buyer, 870_000_00)

    {:ok, workflow} = Magma.start(PrivateTreaty, %{offer_id: offer.id}, queue: :sales)
    run_workflows(queue: :sales)

    negotiation = Magma.child_id(workflow.id, :negotiation)
    assert status(negotiation) == :waiting

    {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :accept})
    run_workflows(queue: :sales)

    assert status(workflow) == :completed

    assert recorded(workflow, :negotiation) == %{
             outcome: :accepted,
             buyer_id: buyer.id,
             offer_id: offer.id,
             price: 870_000_00,
             via: :treaty
           }

    assert Sale.get_offer!(offer.id).status == :accepted
  end
end
