defmodule Payouts.Offramp.Payout do
  @moduledoc """
  A payout, end to end.

  The sequence reads top to bottom, and every line of it is a checkpoint. What the engine
  gives this workflow, that application code would otherwise have to:

  | | |
  |---|---|
  | The quote shown is the amount debited | `debit` reads `quote`'s recorded output, so a replay cannot re-price |
  | The customer is debited once | the debit's checkpoint is what a resumed run replays |
  | A quote that lapses is an error | the confirmation wait's deadline *is* the quote's expiry |
  | A rejected payout is compensated | `debit` implements `undo/4`, and a rejection fails the run |
  | The rail is whichever one serves the currency | `:rail` dispatches a child workflow chosen by `Payouts.Routing` |
  | Only a customer the rail has taken on is paid | `onboarding` and `beneficiary` both stand in front of `quote` |

  No provider is named here. The rail is a module `Payouts.Routing` resolves from the
  transfer's currency, and it runs as a child workflow on its own queue.
  """

  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  alias Payouts.Offramp.Payout.Steps

  magma do
    queue(:payouts)
  end

  input(:transfer_id)

  read_one :transfer, Payouts.Offramp.Transfer, :by_id do
    inputs(%{id: input(:transfer_id)})
    load(value([:customer]))
    fail_on_not_found?(true)
  end

  step :onboarding, Steps.Onboarding do
    argument(:transfer, result(:transfer))
  end

  step :beneficiary, Steps.Beneficiary do
    argument(:transfer, result(:transfer))
    wait_for(:onboarding)
  end

  step :quote, Steps.Quote do
    argument(:transfer, result(:transfer))
    wait_for(:beneficiary)
  end

  await :confirmation do
    signal("confirm")
    timeout(:timer.minutes(15))
    argument(:quote, result(:quote))
  end

  step :debit, Steps.Debit do
    argument(:transfer, result(:transfer))
    argument(:confirmation, result(:confirmation))
  end

  dispatch :rail do
    workflow(&Payouts.Routing.rail_for/2)
    inputs(&Payouts.Offramp.Payout.rail_inputs/2)
    queue(:rails)
    block_ms(50)
    argument(:transfer, result(:transfer))
    argument(:quote, result(:quote))
    argument(:beneficiary, result(:beneficiary))
    wait_for(:debit)
  end

  await :settlement do
    signal("settlement")
    timeout(:timer.hours(24))
    wait_for(:rail)
  end

  step :settle, Steps.Settle do
    argument(:transfer, result(:transfer))
    argument(:settlement, result(:settlement))
  end

  return(:settle)

  @doc """
  Starts the payout for a transfer, under an id derived from the transfer.

  Deriving the id means the console can find a payout from its transfer without storing a
  reference, and asking twice for the same payout starts one workflow.
  """
  @spec start(String.t()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  def start(transfer_id) do
    Magma.start(__MODULE__, %{transfer_id: transfer_id},
      queue: :payouts,
      workflow_id: workflow_id(transfer_id)
    )
  end

  @doc "The workflow id a transfer's payout runs under."
  @spec workflow_id(String.t()) :: String.t()
  def workflow_id(transfer_id), do: Magma.child_id(transfer_id, :payout)

  @doc false
  def rail_inputs(%{transfer: transfer, quote: quote, beneficiary: beneficiary}, _context) do
    %{
      transfer_id: transfer.id,
      destination_amount: quote.destination_amount,
      beneficiary_ref: beneficiary && beneficiary.provider_ref
    }
  end
end
