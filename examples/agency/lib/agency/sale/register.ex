defmodule Agency.Sale.Register do
  @moduledoc "The buyers an agreement keeps, and which of them a further attempt can approach."

  alias Agency.Sale

  @doc """
  Each buyer still on the register paired with the offer worth going back to them on.

  A buyer whose offer in the closed attempt lapsed or was withdrawn has nothing to re-approach
  them with, so they are left out.
  """
  @spec approachable(String.t(), String.t()) ::
          [{Ash.Resource.record(), Ash.Resource.record()}]
  def approachable(agency_agreement_id, sale_attempt_id) do
    offers = Sale.offers_for_attempt!(sale_attempt_id)

    agency_agreement_id
    |> Sale.available_buyers!()
    |> Enum.flat_map(fn buyer ->
      case standing_offer(offers, buyer) do
        nil -> []
        offer -> [{buyer, offer}]
      end
    end)
  end

  defp standing_offer(offers, buyer) do
    offers
    |> Enum.filter(&(&1.buyer_id == buyer.id and &1.status not in [:lapsed, :withdrawn]))
    |> Enum.max_by(& &1.amount, fn -> nil end)
  end
end
