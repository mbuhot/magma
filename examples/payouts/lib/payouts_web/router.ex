defmodule PayoutsWeb.Router do
  @moduledoc false

  use PayoutsWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PayoutsWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", PayoutsWeb do
    pipe_through(:browser)

    live("/", ConsoleLive, :index)
    live("/payouts/:id", PayoutLive, :show)
  end
end
