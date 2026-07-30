defmodule Agency.Sale.Negotiation do
  @moduledoc """
  One round of bargaining over a single offer.

  A round that ends in a counter is a new offer superseding the old one, and a fresh round
  against it. That successor is a child workflow rather than a loop, because a round waits and
  nothing inside a `recurse` may. Each round is its own parent, so the chain is unbounded and
  every child id is distinct.
  """

  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  alias Agency.Sale.Negotiation.Steps
  alias Agency.Sale.Offer
  alias Agency.Sale.Outcome

  magma do
    queue(:sales)
  end

  input(:offer_id)

  read_one :offer, Offer, :by_id do
    inputs(%{id: input(:offer_id)})
    fail_on_not_found?(true)
  end

  await :response do
    signal("negotiation.response")
    argument(:offer, result(:offer))
    timeout(&Steps.response_deadline/2)
    on_timeout(:return)
  end

  step :decision, Steps.Decision do
    argument(:response, result(:response))
  end

  switch :outcome do
    on(result(:decision))

    matches? &(&1 == :accept) do
      update :accept_offer, Offer, :set_status do
        initial(result(:offer))
        inputs(%{status: value(:accepted)})
      end

      step :outcome, Outcome.Accepted do
        argument(:offer, result(:accept_offer))
      end
    end

    matches? &(&1 == :counter) do
      step(:counter_expiry, Steps.CounterExpiry)

      create :counter_offer, Offer, :make do
        inputs(%{
          sale_attempt_id: result(:offer, [:sale_attempt_id]),
          buyer_id: result(:offer, [:buyer_id]),
          amount: result(:response, [:amount]),
          requested_conditions: result(:offer, [:requested_conditions]),
          expires_at: result(:counter_expiry),
          supersedes_id: result(:offer, [:id])
        })
      end

      update :supersede_offer, Offer, :set_status do
        initial(result(:offer))
        inputs(%{status: value(:superseded)})
        wait_for(:counter_offer)
      end

      dispatch :next_round do
        workflow(Agency.Sale.Negotiation)
        queue(:sales)
        argument(:offer_id, result(:counter_offer, [:id]))
        wait_for(:supersede_offer)
      end

      step :outcome, Outcome.Reported do
        argument(:outcome, result(:next_round))
      end
    end

    matches? &(&1 == :withdraw) do
      update :withdraw_offer, Offer, :set_status do
        initial(result(:offer))
        inputs(%{status: value(:withdrawn)})
      end

      step :outcome, {Outcome.NoSale, reason: :withdrawn} do
        wait_for(:withdraw_offer)
      end
    end

    default do
      update :lapse_offer, Offer, :set_status do
        initial(result(:offer))
        inputs(%{status: value(:lapsed)})
      end

      step :outcome, {Outcome.NoSale, reason: :lapsed} do
        wait_for(:lapse_offer)
      end
    end
  end

  return(:outcome)
end
