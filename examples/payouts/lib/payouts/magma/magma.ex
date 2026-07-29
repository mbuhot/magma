defmodule Payouts.Magma do
  @moduledoc "Magma's own rows, owned by this application like any other resource."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(Payouts.Magma.Workflow)
    resource(Payouts.Magma.Checkpoint)
    resource(Payouts.Magma.Signal)
    resource(Payouts.Magma.Waiter)
  end
end
