defmodule Agency.External.SettlementStatus do
  @moduledoc "Where a settlement workspace stands with PEXA."

  use Ash.Type.Enum,
    values: [
      booked: "the workspace is open and waiting on the parties",
      settled: "funds and title moved and the workspace closed",
      defaulted: "the buyer failed to settle and the workspace closed unsettled"
    ]
end
