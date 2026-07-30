defmodule Agency.Sale.AttemptOutcome do
  @moduledoc "Where a sale attempt stands, and how it ended if it has."

  use Ash.Type.Enum,
    values: [
      running: "still open",
      settled: "the contract exchanged and settled",
      rescinded: "the buyer rescinded during cooling off",
      condition_failed: "a condition of the contract was not satisfied",
      buyer_default: "the buyer defaulted at settlement",
      no_offers: "the attempt closed without a single offer"
    ]
end
