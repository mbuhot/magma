defmodule AgencyWeb.Updates do
  @moduledoc """
  What a page listens to while it is open.

  The engine writes a checkpoint for every step it finishes, parks and releases waits as it
  reaches them, and moves a workflow's status as runs start and end. Between them those are
  the whole of "something happened", and what a page offers turns on the waits especially: an
  instruction only lands once the run is parked to hear it.
  """

  @topics ~w(runs:all checkpoints:all waits:all)

  @doc "Follows the engine for as long as this page is open."
  @spec follow() :: :ok
  def follow do
    for topic <- @topics, do: Phoenix.PubSub.subscribe(Agency.PubSub, topic)

    :ok
  end
end
