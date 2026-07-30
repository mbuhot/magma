defmodule HelpdeskWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Magma.Testing, repo: Helpdesk.Repo

      use Phoenix.VerifiedRoutes,
        endpoint: HelpdeskWeb.Endpoint,
        router: HelpdeskWeb.Router,
        statics: HelpdeskWeb.static_paths()

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import Helpdesk.DataCase
      import HelpdeskWeb.ConnCase

      @endpoint HelpdeskWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Helpdesk.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Makes a live view read the store again, and returns what it now shows.

  The page repaints on a timer because the work it starts finishes in another process, so a
  test that drains the queue has to tell it to look.
  """
  def repainted(view) do
    send(view.pid, :refresh)
    Phoenix.LiveViewTest.render(view)
  end
end
