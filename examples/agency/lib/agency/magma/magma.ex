defmodule Agency.Magma do
  @moduledoc "Magma's own rows, owned by this application like any other resource."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(Agency.Magma.Workflow)
    resource(Agency.Magma.Checkpoint)
    resource(Agency.Magma.Signal)
    resource(Agency.Magma.Waiter)
  end
end
