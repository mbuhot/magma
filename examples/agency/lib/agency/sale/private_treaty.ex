defmodule Agency.Sale.PrivateTreaty do
  @moduledoc "A sale by private treaty: one negotiation, against one buyer's offer."

  use Reactor, extensions: [Magma.Dsl]

  magma do
    queue(:sales)
  end

  input(:offer_id)

  dispatch :negotiation do
    workflow(Agency.Sale.Negotiation)
    queue(:sales)
    argument(:offer_id, input(:offer_id))
  end

  return(:negotiation)
end
