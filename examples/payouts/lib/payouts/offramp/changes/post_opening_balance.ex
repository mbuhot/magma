defmodule Payouts.Offramp.Changes.PostOpeningBalance do
  @moduledoc """
  Deposits a new customer's opening balance into the ledger.

  A balance is the sum of what has been posted, so opening one means posting to it.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    amount_cents = Ash.Changeset.get_argument(changeset, :opening_balance_cents)

    Ash.Changeset.after_action(changeset, fn _changeset, customer ->
      with {:ok, _opening} <- post(customer, amount_cents) do
        Payouts.Offramp.get_customer(customer.id)
      end
    end)
  end

  defp post(_customer, 0), do: {:ok, nil}

  defp post(customer, amount_cents) do
    Payouts.Offramp.post_ledger_entry(%{
      customer_id: customer.id,
      amount_cents: amount_cents,
      reason: "opening balance"
    })
  end
end
