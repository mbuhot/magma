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

  @doc """
  What a live view shows once the work a click started has run.

  The queues are worked by Oban itself in a deployment, and the page repaints on what the
  engine publishes as it goes. A test holds the queues still, so it runs them itself and then
  reads the page the way the browser would have.
  """
  def acted(view) do
    Agency.DataCase.run_agency()

    repainted(view)
  end
end
