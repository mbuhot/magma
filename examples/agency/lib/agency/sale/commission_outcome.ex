defmodule Agency.Sale.CommissionOutcome do
  @moduledoc "Where an accrued commission ended up."

  use Ash.Type.Enum,
    values: [
      accrued: "entitlement recorded, not yet paid",
      disbursed: "paid out",
      written_back: "the entitlement was reversed after the sale failed"
    ]
end
