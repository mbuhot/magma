defmodule HelpdeskWeb.Router do
  @moduledoc false

  use HelpdeskWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {HelpdeskWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", HelpdeskWeb do
    pipe_through(:browser)

    live("/", QueueLive, :index)
    live("/tickets/:id", TicketLive, :show)
  end
end
