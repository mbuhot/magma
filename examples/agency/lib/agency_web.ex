defmodule AgencyWeb do
  @moduledoc """
  The application's web layer: an endpoint and a router.

  Small on purpose. There is no asset pipeline and no LiveViews yet.
  """

  def static_paths, do: ~w(favicon.ico)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]

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
