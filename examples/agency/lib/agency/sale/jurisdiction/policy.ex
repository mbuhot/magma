defmodule Agency.Sale.Jurisdiction.Policy do
  @moduledoc "A jurisdiction's cooling-off terms: how long, at what forfeit, and whether auction exempts it."

  @enforce_keys [:business_days, :forfeit_rate, :auction]
  defstruct [:business_days, :forfeit_rate, :auction]

  @type t :: %__MODULE__{
          business_days: pos_integer(),
          forfeit_rate: Decimal.t(),
          auction: :exempt | :applies
        }
end
