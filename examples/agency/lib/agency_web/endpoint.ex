defmodule AgencyWeb.Endpoint do
  @moduledoc "The application's endpoint."

  use Phoenix.Endpoint, otp_app: :agency

  @session_options [
    store: :cookie,
    key: "_agency_key",
    signing_salt: "hQ4mZ7dK",
    same_site: "Lax"
  ]

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
  plug(AgencyWeb.Router)
end
