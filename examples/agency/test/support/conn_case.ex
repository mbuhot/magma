defmodule AgencyWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Magma.Testing, repo: Agency.Repo

      use Phoenix.VerifiedRoutes,
        endpoint: AgencyWeb.Endpoint,
        router: AgencyWeb.Router,
        statics: AgencyWeb.static_paths()

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import Agency.DataCase
      import AgencyWeb.ConnCase

      @endpoint AgencyWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Agency.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "What a live view shows once it has taken in everything already committed."
  def repainted(view), do: Phoenix.LiveViewTest.render(view)
end
