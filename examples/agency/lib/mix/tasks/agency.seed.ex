defmodule Mix.Tasks.Agency.Seed do
  @shortdoc "Resets and seeds four listings parked at different points in the sale workflow"
  @moduledoc """
  Wipes this example's tables and rebuilds four listings by driving their workflows forward to
  a deliberately parked wait, so the sales desk and console both open with the branching already
  visible.

  The queues are held still in this task's own node while it runs: seeding drives the engine
  itself, step by step, and a queue working in parallel would race it. A server running
  alongside keeps working.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    if Mix.env() == :test do
      Mix.raise("mix agency.seed must run against a development database, not the test one")
    end

    Mix.Task.run("app.start")
    Application.put_env(:magma, :block_ms, 0)
    Oban.pause_all_queues(local_only: true)

    Agency.Seeds.reset!()
    Agency.Seeds.seed!()

    Mix.shell().info(
      "Seeded 14 Kurraba Road, 8 Rialto Street, 22 Ardoyne Road and 51 Marine Parade."
    )
  end
end
