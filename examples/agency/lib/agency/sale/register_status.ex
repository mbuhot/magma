defmodule Agency.Sale.RegisterStatus do
  @moduledoc "Where a buyer stands against the property, across every attempt."

  use Ash.Type.Enum,
    values: [
      available: "still interested and able to be re-approached",
      under_contract: "presently the buyer on an exchanged contract",
      missed: "was outbid or the vendor chose another buyer",
      withdrew: "pulled out of contention",
      rescinded: "exchanged and then rescinded during cooling off",
      defaulted: "exchanged and then defaulted at settlement"
    ]
end
