defmodule Magma.Pruner do
  @moduledoc """
  An Oban worker that prunes what has outlived its retention.

  Schedule it with Oban's cron plugin, at whatever interval suits the shortest retention you
  have set:

      config :my_app, Oban,
        plugins: [
          {Oban.Plugins.Cron, crontab: [{"0 * * * *", Magma.Pruner}]}
        ]

  `limit` in the job's args caps one pass, so a long backlog is worked through over several.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl true
  def perform(%Oban.Job{args: args}) do
    limit = Map.get(args, "limit", 1_000)

    {:ok, pruned} = Magma.Retention.prune(limit: limit)

    {:ok, %{pruned: pruned}}
  end
end
