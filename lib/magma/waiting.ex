defmodule Magma.Waiting do
  @moduledoc "What a parked step is waiting for."

  use Ash.Type.Enum,
    values: [
      signal: "something will push it — a webhook, an approval, a sibling workflow",
      poll: "nothing will push it, so it checks again on an interval"
    ]
end
