defmodule Agency.Sale.Jurisdiction do
  @moduledoc "The state whose rules govern a property's sale."

  use Ash.Type.Enum,
    values: [
      nsw: "New South Wales",
      vic: "Victoria",
      qld: "Queensland"
    ]
end
