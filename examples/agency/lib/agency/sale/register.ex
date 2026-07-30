defmodule Agency.Sale.Register do
  @moduledoc "The buyers an agreement keeps, and which of them a further attempt can approach."

  alias Agency.Sale

  @doc """
  Each buyer still on the register paired with the offer worth going back to them on.

  The register belongs to the agreement rather than to any one generation, so a buyer passed
  over in an earlier attempt stays reachable. What they would be re-approached on is the last
  thing they said, and a buyer whose last word was to let an offer lapse or to pull it has
  nothing to re-approach them with.
  """
  @spec approachable(String.t()) :: [{Ash.Resource.record(), Ash.Resource.record()}]
  def approachable(agency_agreement_id) do
    offers = offers_across_the_agreement(agency_agreement_id)

    agency_agreement_id
    |> Sale.available_buyers!()
    |> Enum.flat_map(fn buyer ->
      case standing_offer(offers, buyer) do
        nil -> []
        offer -> [{buyer, offer}]
      end
    end)
  end

  defp offers_across_the_agreement(agency_agreement_id) do
    agency_agreement_id
    |> Sale.attempts_for_agreement!()
    |> Enum.flat_map(&Sale.offers_for_attempt!(&1.id))
  end

  defp standing_offer(offers, buyer) do
    offers
    |> Enum.filter(&(&1.buyer_id == buyer.id))
    |> Enum.max_by(& &1.id, fn -> nil end)
    |> case do
      %{status: status} when status in [:lapsed, :withdrawn] -> nil
      latest -> latest
    end
  end
end
