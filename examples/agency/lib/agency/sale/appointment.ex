defmodule Agency.Sale.Appointment do
  @moduledoc "How exclusively an agent holds the right to sell."

  use Ash.Type.Enum,
    values: [
      exclusive: "one agent, no other agent or the vendor may sell",
      sole: "one agent, the vendor may still sell privately",
      open: "any number of agents compete for the sale"
    ]
end
