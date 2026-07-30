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
  What a live view shows once it has taken in everything published to it.

  Rendering is a call, so anything already in the view's mailbox — the notifications a write
  in this test, or in a job it drained, sent — is handled before the render is answered.
  """
  def repainted(view), do: Phoenix.LiveViewTest.render(view)
end
