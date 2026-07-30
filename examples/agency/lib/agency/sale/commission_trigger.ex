defmodule Agency.Sale.CommissionTrigger do
  @moduledoc "When an accrued commission is paid out."

  use Ash.Type.Enum,
    values: [
      on_settlement: "paid from the deposit held in trust at settlement",
      on_unconditional: "brought forward to when the contract goes unconditional"
    ]
end
