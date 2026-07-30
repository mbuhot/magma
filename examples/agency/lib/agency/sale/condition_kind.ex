defmodule Agency.Sale.ConditionKind do
  @moduledoc "A category of condition a contract can be subject to."

  use Ash.Type.Enum,
    values: [
      finance: "the buyer's lender approving the loan",
      inspection: "a building or pest inspection",
      title: "a clean title search"
    ]
end
