defmodule HelpdeskWeb do
  @moduledoc """
  The console's web layer: an endpoint, a router and two live views.

  Small on purpose. There is no asset pipeline — the LiveView client is served straight out
  of its own package and the stylesheet is a string in `HelpdeskWeb.Layouts`.
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

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {HelpdeskWeb.Layouts, :app}

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
        endpoint: HelpdeskWeb.Endpoint,
        router: HelpdeskWeb.Router,
        statics: HelpdeskWeb.static_paths()

      alias Phoenix.LiveView.JS
      alias HelpdeskWeb.Layouts
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
