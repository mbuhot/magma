defmodule Agency.Sale.Auction do
  @moduledoc """
  A sale by auction: a reserve, a campaign, and the hammer.

  Sold on the day is terms straight away. Passed in falls through to a private treaty against
  the highest bidder, and ends unsold when the auction drew nobody to negotiate with.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Agency.Sale.Auction.Steps
  alias Agency.Sale.Outcome
  alias Agency.Sale.Window

  magma do
    queue(:sales)
  end

  input(:sale_attempt_id)
  input(:reserve)

  step :reserve_set, Steps.ReserveSet do
    argument(:sale_attempt_id, input(:sale_attempt_id))
    argument(:reserve, input(:reserve))
  end

  await :hammer do
    signal("auction.hammer")
    timeout(Window.auction_day())
    wait_for(:reserve_set)
  end

  step :highest_bidder, Steps.HighestBidder do
    argument(:sale_attempt_id, input(:sale_attempt_id))
    wait_for(:hammer)
  end

  step :verdict, Steps.Verdict do
    argument(:hammer, result(:hammer))
    argument(:highest_bidder, result(:highest_bidder))
  end

  switch :outcome do
    on(result(:verdict))

    matches? &(&1 == :sold) do
      step :outcome, Steps.Sold do
        argument(:hammer, result(:hammer))
      end
    end

    matches? &(&1 == :treaty) do
      dispatch :treaty do
        workflow(Agency.Sale.PrivateTreaty)
        queue(:sales)
        argument(:offer_id, result(:highest_bidder, [:id]))
      end

      step :outcome, Outcome.Reported do
        argument(:outcome, result(:treaty))
      end
    end

    default do
      step(:outcome, {Outcome.NoSale, reason: :passed_in_unsold})
    end
  end

  return(:outcome)
end
