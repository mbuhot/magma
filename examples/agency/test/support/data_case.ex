defmodule Agency.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Magma.Testing, repo: Agency.Repo

      import Agency.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Agency.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    :ok
  end
end
