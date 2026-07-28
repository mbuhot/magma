defmodule Magma do
  @moduledoc """
  Durable workflows for Ash.

  A Reactor runs inside an Oban job and every step checkpoints its output. Each later
  attempt rebuilds the reactor from its DSL, replays the outputs already recorded, and
  carries on from the edge of what finished.

  This module is the public surface: starting a workflow, awaiting its result, delivering a
  signal to one that is waiting, and cancelling one.
  """

  @doc """
  Records a workflow and enqueues the job that will run it.

  Returns the workflow row, whose id is the handle for everything else here.

      {:ok, workflow} = Magma.start(MyApp.Checkout, %{order_id: id}, actor: current_user)
  """
  @spec start(module(), map(), keyword()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  defdelegate start(module, inputs \\ %{}, options \\ []), to: Magma.Api

  @doc """
  Stops a workflow and takes back everything it has done.

  A workflow that is waiting holds no process and no job, so this writes its status and
  enqueues the job that drives the rollback from its checkpoints.
  """
  @spec cancel(String.t()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  defdelegate cancel(workflow_id), to: Magma.Api

  @doc "What the store last recorded for a workflow."
  @spec fetch(String.t()) :: {:ok, Ash.Resource.record() | nil} | {:error, term()}
  defdelegate fetch(workflow_id), to: Magma.Store, as: :get_workflow

  @doc "Every step a workflow has recorded that still stands, newest first."
  @spec steps(String.t()) :: [Ash.Resource.record()]
  defdelegate steps(workflow_id), to: Magma.Store, as: :standing
end
