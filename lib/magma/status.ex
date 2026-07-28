defmodule Magma.Status do
  @moduledoc """
  Where a workflow stands.

  `pending` covers a run that is executing or waiting to be picked up. The three parked
  states name what it is parked on. The terminal three are the ways a run ends.
  """

  use Ash.Type.Enum,
    values: [
      pending: "running, or waiting for a worker to pick it up",
      waiting: "parked on a signal, holding no process and no job",
      polling: "parked between polls, snoozed as an Oban job",
      unwinding: "has taken work back and is committed to taking back the rest",
      completed: "finished, with a result",
      failed: "ended on an error, with whatever could be unwound taken back",
      cancelled: "ended on a cancellation, with whatever could be unwound taken back"
    ]

  @terminal ~w[completed failed cancelled]a

  @doc "Whether a workflow in this state has stopped for good."
  @spec terminal?(t()) :: boolean()
  def terminal?(status), do: status in @terminal
end
