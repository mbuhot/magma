defmodule Payouts.Rails.Bridge do
  @moduledoc """
  The EUR rail.

  Funds a vault before it sends, so it has a step the other rail does not. The spine knows
  none of that.
  """

  use Reactor, extensions: [Magma.Dsl]

  magma do
    queue(:rails)
  end

  input(:transfer_id)
  input(:destination_amount)
  input(:beneficiary_ref)

  step :fund, Payouts.Rails.Bridge.Fund do
    argument(:destination_amount, input(:destination_amount))
  end

  step :send, Payouts.Rails.Bridge.Send do
    argument(:transfer_id, input(:transfer_id))
    argument(:destination_amount, input(:destination_amount))
    argument(:beneficiary_ref, input(:beneficiary_ref))
    argument(:funding, result(:fund))
  end

  return(:send)

  defmodule Fund do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{destination_amount: amount}, _context, _options) do
      {:ok, Payouts.Provider.fund_vault(amount)}
    end
  end

  defmodule Send do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      %{transfer_id: id, destination_amount: amount, beneficiary_ref: ref} = arguments

      Payouts.Provider.send_payout(id, amount, ref)
    end
  end
end
