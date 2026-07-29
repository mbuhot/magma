defmodule Payouts.Offramp.TransferStatus do
  @moduledoc "Where a transfer stands in its lifecycle."

  use Ash.Type.Enum,
    values: [
      requested: "waiting for the customer to confirm the quote they were shown",
      expired: "the quote lapsed before it was confirmed",
      debited: "the customer's balance has been taken",
      sent: "handed to the provider, waiting on settlement",
      completed: "settled",
      reversed: "the debit was posted back, and the payout did not happen"
    ]
end
