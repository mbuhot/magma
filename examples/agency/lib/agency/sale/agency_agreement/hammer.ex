defmodule Agency.Sale.AgencyAgreement.Hammer do
  @moduledoc "What the auctioneer's hammer says about the offer standing when it falls."

  alias Agency.Sale

  @doc "The sale payload for whichever offer is still live on the listing's latest attempt."
  @spec payload(Ash.Resource.record(), map()) :: map()
  def payload(listing, _arguments) do
    attempt = listing.id |> Sale.attempts_for_agreement!() |> List.last()
    offer = attempt.id |> Sale.live_offers_for_attempt!() |> List.first()

    %{result: :sold, buyer_id: offer.buyer_id, offer_id: offer.id, price: offer.amount}
  end
end
