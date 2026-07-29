defmodule Payouts.Offramp.Unregistered do
  @moduledoc "Raised when a rail that pays a third party has no account registered to pay."

  defexception [:customer_id, :destination_currency]

  @impl true
  def message(%{customer_id: customer_id, destination_currency: currency}) do
    "customer #{customer_id} has no registered #{currency} beneficiary"
  end
end
