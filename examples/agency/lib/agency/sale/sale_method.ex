defmodule Agency.Sale.SaleMethod do
  @moduledoc "The process by which the property is put to market."

  use Ash.Type.Enum,
    values: [
      auction: "sold under the hammer on the day",
      set_date: "offers are invited by a deadline",
      treaty: "negotiated privately, no set deadline"
    ]
end
