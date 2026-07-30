defmodule Agency.Sale.SaleMethod do
  @moduledoc "The process by which the property is put to market."

  use Ash.Type.Enum,
    values: [
      auction: "sold under the hammer on the day",
      set_date: "offers are invited by a deadline",
      treaty: "negotiated privately, no set deadline"
    ]

  @doc "How the kind is written on screen."
  @spec label(atom()) :: String.t()
  def label(:auction), do: "Auction"
  def label(:set_date), do: "Set date sale"
  def label(:treaty), do: "Private treaty"
end
