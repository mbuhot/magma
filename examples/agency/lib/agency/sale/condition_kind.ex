defmodule Agency.Sale.ConditionKind do
  @moduledoc "A category of condition a contract can be subject to."

  use Ash.Type.Enum,
    values: [
      finance: "the buyer's lender approving the loan",
      inspection: "a building or pest inspection",
      title: "a clean title search"
    ]

  @doc "How the kind is written on screen."
  @spec label(atom()) :: String.t()
  def label(:finance), do: "Finance"
  def label(:inspection), do: "Building & pest"
  def label(:title), do: "Title"
end
