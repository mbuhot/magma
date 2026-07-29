defmodule Payouts.Offramp.BeneficiaryStatus do
  @moduledoc "Whether the rail has accepted a payout destination yet."

  use Ash.Type.Enum,
    values: [
      recorded: "the customer gave us the account, the rail has not been told",
      registered: "the rail holds this account and will pay it"
    ]
end
