defmodule Magma do
  @moduledoc """
  Durable workflows for Ash.

  A Reactor runs inside an Oban job and every step checkpoints its output. Each later
  attempt rebuilds the reactor from its DSL, replays the outputs already recorded, and
  carries on from the edge of what finished.

  This module is the public surface: starting a workflow, awaiting its result, delivering a
  signal to one that is waiting, and cancelling one.
  """
end
