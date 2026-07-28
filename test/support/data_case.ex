defmodule Magma.DataCase do
  @moduledoc "A case template for tests that read and write magma's resources."

  use ExUnit.CaseTemplate

  using do
    quote do
      import Magma.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Magma.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
