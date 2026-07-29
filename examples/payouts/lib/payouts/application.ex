defmodule Payouts.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Payouts.Repo,
      Payouts.Provider,
      Magma.Notifier,
      {Oban, Application.fetch_env!(:payouts, Oban)},
      {Phoenix.PubSub, name: Payouts.PubSub},
      PayoutsWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Payouts.Supervisor)
  end
end
