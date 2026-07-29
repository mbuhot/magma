defmodule PayoutsWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Magma.Testing, repo: Payouts.Repo

      use Phoenix.VerifiedRoutes,
        endpoint: PayoutsWeb.Endpoint,
        router: PayoutsWeb.Router,
        statics: PayoutsWeb.static_paths()

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import Payouts.DataCase
      import PayoutsWeb.ConnCase

      @endpoint PayoutsWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Payouts.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    owner = self()
    Payouts.Provider.open()
    on_exit(fn -> Payouts.Provider.close(owner) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Runs everything that is ready on every queue, until nothing is.

  A payout hands work to a rail on another queue and the rail signals back, so one pass over
  one queue is never the whole of it.
  """
  def settle_queues(passes \\ 4) do
    Enum.each(1..passes, fn _pass ->
      for queue <- [:onboarding, :rails, :payouts] do
        Oban.drain_queue(queue: queue, with_recursion: true, with_safety: false)
      end
    end)
  end

  @doc """
  Makes a live view read the store again, and returns what it now shows.

  The page repaints on a timer because the work it starts finishes in another process, so a
  test that drains the queues has to tell it to look.
  """
  def repainted(view) do
    send(view.pid, :refresh)
    Phoenix.LiveViewTest.render(view)
  end
end
