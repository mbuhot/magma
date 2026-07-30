defmodule Agency.Sale.OfferStatus do
  @moduledoc "Where an offer stands in a negotiation."

  use Ash.Type.Enum,
    values: [
      live: "open and awaiting a response",
      countered: "the vendor came back with different terms",
      final: "the vendor's last position, unable to be countered further",
      accepted: "the vendor accepted, and it became a contract",
      superseded: "replaced by a later offer from the same negotiation",
      lapsed: "expired without a response",
      withdrawn: "the buyer pulled it"
    ]
end
