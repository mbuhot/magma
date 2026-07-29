defmodule PayoutsWeb.Endpoint do
  @moduledoc """
  The console's endpoint.

  The two JavaScript files it serves are the prebuilt bundles that ship inside `phoenix` and
  `phoenix_live_view`, mounted from their own packages, so the example has no asset build.
  """

  use Phoenix.Endpoint, otp_app: :payouts

  @session_options [
    store: :cookie,
    key: "_payouts_key",
    signing_salt: "3xB1kQ2m",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/vendor/live_view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(PayoutsWeb.Router)
end
