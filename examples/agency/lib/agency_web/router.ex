defmodule AgencyWeb.Router do
  @moduledoc false

  use AgencyWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {AgencyWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", AgencyWeb do
    pipe_through(:browser)

    live("/", ListingLive, :index)
    live("/listings/:id", ListingLive, :show)
    live("/console", ConsoleLive, :index)
    live("/console/:id", ConsoleLive, :show)
  end
end
