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
  Delivers a signal to a workflow, waking it if it is parked on that name.

  The signal and the job that brings the workflow back commit together, so a crash on the
  sending side cannot leave a parked workflow with nothing coming for it.

      Magma.signal(workflow.id, "confirm", %{approver: "sam"})
  """
  @spec signal(String.t(), String.t(), term()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  defdelegate signal(workflow_id, name, payload \\ nil), to: Magma.Api

  @doc """
  Stops a workflow and takes back everything it has done.

  A workflow that is waiting holds no process and no job, so this writes its status and
  enqueues the job that drives the rollback from its checkpoints.
  """
  @spec cancel(String.t()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  defdelegate cancel(workflow_id), to: Magma.Api

  @doc "A stable id for a child a step dispatches, derived from its parent and the step."
  @spec child_id(String.t(), term()) :: String.t()
  defdelegate child_id(parent_workflow_id, step_name), to: Magma.Key, as: :child_id

  @doc """
  Deletes the workflows that have outlived their retention, and everything belonging to them.

  Retention comes from the workflow's own `magma` section, falling back to
  `config :magma, retention: ...` and then to `:infinity`. Nothing is deleted by default.
  """
  @spec prune(keyword()) :: {:ok, non_neg_integer()}
  defdelegate prune(options \\ []), to: Magma.Retention

  @doc "What the store last recorded for a workflow."
  @spec fetch(String.t()) :: {:ok, Ash.Resource.record() | nil} | {:error, term()}
  defdelegate fetch(workflow_id), to: Magma.Store, as: :get_workflow

  @doc "Every step a workflow has recorded that still stands, newest first."
  @spec steps(String.t()) :: [Ash.Resource.record()]
  defdelegate steps(workflow_id), to: Magma.Store, as: :standing
end
