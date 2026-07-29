defmodule Payouts.Rails.Meridian do
  @moduledoc """
  The USD rail.

  A wire to the customer's own account: no funding, no beneficiary, one step. Its config entry
  is the only thing that differs from the other rail's, as far as the spine is concerned.
  """

  use Reactor, extensions: [Magma.Dsl]

  magma do
    queue(:rails)
  end

  input(:transfer_id)
  input(:destination_amount)

  step :send, Payouts.Rails.Meridian.Send do
    argument(:transfer_id, input(:transfer_id))
    argument(:destination_amount, input(:destination_amount))
  end

  return(:send)

  defmodule Send do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{transfer_id: id, destination_amount: amount}, _context, _options) do
      Payouts.Provider.send_payout(id, amount)
    end
  end
end
