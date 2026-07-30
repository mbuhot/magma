defmodule Agency.Sale.ConditionStatus do
  @moduledoc "Where a single contract condition stands."

  use Ash.Type.Enum,
    values: [
      pending: "not yet resolved",
      satisfied: "resolved in the buyer's favour",
      failed: "resolved against the buyer"
    ]
end
