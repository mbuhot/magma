defmodule Magma.Test.Store do
  @moduledoc "The domain magma's resources live in for the suite."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Magma.Test.Store.Workflow
    resource Magma.Test.Store.Checkpoint
    resource Magma.Test.Store.Signal
    resource Magma.Test.Store.Waiter
  end
end
