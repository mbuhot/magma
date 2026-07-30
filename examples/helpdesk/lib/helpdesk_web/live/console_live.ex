defmodule HelpdeskWeb.ConsoleLive do
  @moduledoc false
  use HelpdeskWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns), do: ~H"<div></div>"
end
