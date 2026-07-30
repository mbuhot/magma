defmodule AgencyWeb do
  @moduledoc """
  The application's web layer: an endpoint, a router, and the sales desk live view.

  Small on purpose. There is no asset pipeline — the LiveView client is served straight out
  of its own package and the stylesheet lives in `AgencyWeb.Layouts`.
  """

  def static_paths, do: ~w(vendor favicon.ico)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]

      unquote(html_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {AgencyWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: AgencyWeb.Endpoint,
        router: AgencyWeb.Router,
        statics: AgencyWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
