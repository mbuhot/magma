defmodule Agency.Sale.DepositStatus do
  @moduledoc "Where a deposit held in trust stands."

  use Ash.Type.Enum,
    values: [
      held: "in trust, contract still on foot",
      released: "paid to the vendor at settlement",
      refunded: "returned to the buyer in full",
      forfeited: "taken by the vendor, or the state's share of it, after a failed contract"
    ]
end
