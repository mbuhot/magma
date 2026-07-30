defmodule Helpdesk.Magma do
  @moduledoc "Magma's own rows, owned by this application like any other resource."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(Helpdesk.Magma.Workflow)
    resource(Helpdesk.Magma.Checkpoint)
    resource(Helpdesk.Magma.Signal)
    resource(Helpdesk.Magma.Waiter)
  end
end
