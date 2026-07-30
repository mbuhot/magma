defmodule Agency.Sale.SetDateSaleTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.SetDateSale

  setup do
    attempt = a_listing(:set_date)

    offers =
      [{"Jordan Lee", 860_000_00}, {"Alex Moreau", 900_000_00}, {"Nina Patel", 880_000_00}]
      |> Enum.map(fn {name, amount} -> an_offer(attempt, a_buyer(attempt, name), amount) end)
      |> Enum.sort_by(& &1.id)

    %{attempt: attempt, offers: offers}
  end

  defp collect_offers(attempt) do
    {:ok, workflow} =
      Magma.start(
        SetDateSale,
        %{sale_attempt_id: attempt.id, offer_deadline: ~U[2026-08-20 17:00:00Z]},
        queue: :sales
      )

    run_workflows(queue: :sales)

    {:ok, _signal} = Magma.signal(workflow.id, "set_date.offers_close", %{})
    run_workflows(queue: :sales)

    workflow
  end

  defp answer_every_offer(workflow, count, payload) do
    Enum.each(0..(count - 1), fn index ->
      child =
        Magma.child_id(workflow.id, {Reactor.Step.Map, :negotiations, :negotiation, index})

      assert status(child) == :waiting

      {:ok, _signal} = Magma.signal(child, "negotiation.response", payload)
      run_workflows(queue: :sales)
    end)
  end

  defp choose(workflow, offer) do
    {:ok, _signal} =
      Magma.signal(workflow.id, "set_date.vendor_selection", %{offer_id: offer.id})

    run_workflows(queue: :sales)
  end

  test "the offer the vendor chooses becomes the terms and the rest are marked missed", context do
    %{offers: [first, second, third]} = context

    workflow = collect_offers(context.attempt)
    answer_every_offer(workflow, 3, %{decision: :accept})

    assert status(workflow) == :waiting

    choose(workflow, second)

    assert status(workflow) == :completed

    assert recorded(workflow, :outcome) == %{
             outcome: :accepted,
             buyer_id: second.buyer_id,
             offer_id: second.id,
             price: second.amount,
             via: :treaty
           }

    assert Sale.get_offer!(second.id).status == :accepted
    assert Sale.get_offer!(first.id).status == :missed
    assert Sale.get_offer!(third.id).status == :missed
  end

  test "a set date sale every buyer pulls out of ends without terms", context do
    workflow = collect_offers(context.attempt)

    answer_every_offer(workflow, 3, %{decision: :withdraw})

    assert status(workflow) == :completed
    assert recorded(workflow, :outcome) == %{outcome: :no_sale, reason: :withdrawn}
    assert Enum.map(Sale.list_offers!(), & &1.status) == [:withdrawn, :withdrawn, :withdrawn]
  end

  test "a set date sale that already chose answers a replay without moving any offer", context do
    %{offers: [first, second, third]} = context

    workflow = collect_offers(context.attempt)
    answer_every_offer(workflow, 3, %{decision: :accept})
    choose(workflow, second)

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert length(Sale.list_offers!()) == 3
    assert Sale.get_offer!(second.id).status == :accepted
    assert Sale.get_offer!(first.id).status == :missed
    assert Sale.get_offer!(third.id).status == :missed
  end
end
