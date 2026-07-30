defmodule Agency.Sale.SetDateSale do
  @moduledoc """
  A sale by set date: offers close, every live one is negotiated at once, and the vendor picks.

  Each offer gets its own child negotiation, so each carries its own response signal and its own
  counter chain. The offers the vendor passed over are marked missed once the choice is made.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Agency.Sale.Outcome
  alias Agency.Sale.SetDateSale.Steps

  magma do
    queue(:sales)
  end

  input(:sale_attempt_id)
  input(:offer_deadline)

  await :offers_close do
    signal("set_date.offers_close")
    argument(:offer_deadline, input(:offer_deadline))
    timeout(&Steps.offers_close_deadline/2)
    on_timeout(:return)
  end

  step :live_offers, Steps.LiveOffers do
    argument(:sale_attempt_id, input(:sale_attempt_id))
    wait_for(:offers_close)
  end

  map :negotiations do
    source(result(:live_offers))

    dispatch :negotiation do
      workflow(Agency.Sale.Negotiation)
      queue(:sales)
      argument(:offer_id, element(:negotiations))
    end

    return(:negotiation)
  end

  step :accepted, Steps.AcceptedTerms do
    argument(:negotiations, result(:negotiations))
  end

  switch :outcome do
    on(result(:accepted))

    matches? &(&1 == []) do
      step(:outcome, {Outcome.NoSale, reason: :withdrawn})
    end

    default do
      await :vendor_selection do
        signal("set_date.vendor_selection")
        argument(:accepted, result(:accepted))
        timeout(&Steps.vendor_selection_deadline/2)
        on_timeout(:return)
      end

      step :missed, Steps.Missed do
        argument(:accepted, result(:accepted))
        argument(:selection, result(:vendor_selection))
      end

      step :outcome, Steps.Selected do
        argument(:accepted, result(:accepted))
        argument(:selection, result(:vendor_selection))
        wait_for(:missed)
      end
    end
  end

  return(:outcome)
end
