defmodule Agency.External.FinanceStatus do
  @moduledoc "Where a buyer's finance application stands with their lender."

  use Ash.Type.Enum,
    values: [
      assessing: "the lender is still assessing the application",
      approved: "the lender has approved the loan",
      declined: "the lender has declined the loan"
    ]
end
