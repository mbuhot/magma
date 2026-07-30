defmodule Agency.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Agency.Repo,
      Magma.Notifier,
      {Oban, Application.fetch_env!(:agency, Oban)},
      {Phoenix.PubSub, name: Agency.PubSub},
      AgencyWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Agency.Supervisor)
  end
end
