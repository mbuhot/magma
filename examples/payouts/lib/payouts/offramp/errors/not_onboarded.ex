defmodule Payouts.Offramp.NotOnboarded do
  @moduledoc "Raised when a rail has not yet accepted the customer a payout is for."

  defexception [:customer_id, :destination_currency, :status]

  @impl true
  def message(%{customer_id: customer_id, destination_currency: currency, status: nil}) do
    "customer #{customer_id} has not been onboarded on the #{currency} rail"
  end

  def message(%{customer_id: customer_id, destination_currency: currency, status: status}) do
    "customer #{customer_id} stands at #{status} on the #{currency} rail"
  end
end
