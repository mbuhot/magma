defmodule Magma.Api do
  @moduledoc false

  alias Magma.Store
  alias Magma.Worker

  @parked [:waiting, :polling]
  @unwinding [:unwinding, :cancelling]
  @terminal [:completed, :failed, :cancelled]

  def start(module, inputs, options) do
    attrs =
      %{
        module: module,
        inputs: inputs,
        actor: options[:actor],
        tenant: options[:tenant]
      }
      |> put_if(:id, options[:workflow_id])
      |> put_parent(options[:parent])

    case running(attrs[:id]) do
      {:ok, workflow} -> {:ok, workflow}
      :none -> insert(attrs, options)
    end
  end

  # A workflow already under this id is the one the caller asked for, and it has a job of its
  # own, so it is handed back rather than started a second time. Asked before inserting rather
  # than after colliding, because a caller inside a transaction of its own would have that
  # transaction aborted by the collision, leaving no read to adopt with.
  defp running(nil), do: :none

  defp running(id) do
    case Store.get_workflow(id) do
      {:ok, workflow} when not is_nil(workflow) -> {:ok, workflow}
      _otherwise -> :none
    end
  end

  # The row and the job that runs it commit together, so a crash on the starting side cannot
  # leave a workflow that nothing will ever pick up.
  # Two callers can still reach this at the same moment, and the primary key settles it. The
  # loser is told, rather than handed the winner's row: its transaction has done work on the
  # assumption that it was the one starting this workflow, and that assumption was wrong.
  defp insert(attrs, options) do
    :workflow
    |> Store.resource()
    |> Ash.transact(fn ->
      with {:ok, workflow} <- Store.start_workflow(attrs),
           {:ok, _job} <- enqueue(workflow, options) do
        workflow
      end
    end)
  end

  defp put_if(attrs, _key, nil), do: attrs
  defp put_if(attrs, key, value), do: Map.put(attrs, key, value)

  defp put_parent(attrs, nil), do: attrs

  defp put_parent(attrs, {parent_id, signal}) do
    Map.merge(attrs, %{parent_workflow_id: parent_id, parent_signal: signal})
  end

  @doc "Tells a workflow's parent how it ended, if it has one."
  def report_to_parent(%{parent_workflow_id: nil}, _outcome), do: :ok

  def report_to_parent(%{parent_workflow_id: parent_id, parent_signal: signal}, outcome) do
    {:ok, _signal} = signal(parent_id, signal, outcome)
    :ok
  end

  # `Ash.transact` rolls back on an error the function returns, and holds the notifications
  # raised inside until it has committed.
  def signal(workflow_id, name, payload) do
    :signal
    |> Store.resource()
    |> Ash.transact(fn ->
      with {:ok, signal} <- Store.deliver_signal(workflow_id, name, payload),
           :ok <- resume(workflow_id) do
        signal
      end
    end)
    |> case do
      {:ok, signal} ->
        Magma.Notifier.broadcast(workflow_id, name)
        {:ok, signal}

      error ->
        error
    end
  end

  @doc "Brings a parked workflow back now."
  def wake(workflow_id) do
    :workflow
    |> Store.resource()
    |> Ash.transact(fn -> resume(workflow_id) end)
    |> case do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  # The signal and the job that brings the workflow back commit together, so a crash on the
  # sending side cannot leave a parked workflow with nothing coming for it.
  #
  # The workflow's row is read holding it, and an attempt claims that same row for as long as it
  # runs, so a delivery and an attempt cannot each act on what the other is about to write.
  defp resume(workflow_id) do
    case Store.lock_workflow(workflow_id) do
      {:ok, workflow} when not is_nil(workflow) ->
        if needs_an_attempt?(workflow) do
          with {:ok, _job} <- enqueue(workflow, []), do: :ok
        else
          :ok
        end

      {:ok, nil} ->
        :ok

      error ->
        error
    end
  end

  # A parked workflow gets the job whatever it is parked on, rather than only when it is parked on
  # this name: the wait the signal answers may be one the run has not reached yet, and the attempt
  # that reaches it needs something to run it.
  #
  # An attempt already under way is no use for a delivery landing now, since it may be past the
  # wait that wanted it, so a held workflow is sent a job of its own. A job waiting its turn is
  # another matter: it starts after this commits, so it reads the delivery for itself.
  #
  # A rollback drives itself from its own job, and an ending is final.
  defp needs_an_attempt?(%{status: status}) when status in @terminal, do: false
  defp needs_an_attempt?(%{status: status}) when status in @unwinding, do: false
  defp needs_an_attempt?(%{status: status}) when status in @parked, do: true
  defp needs_an_attempt?(%{claimed_at: claimed_at}), do: not is_nil(claimed_at)

  # A deadline needs something to bring the workflow back at it, since a parked workflow holds
  # no job of its own.
  def schedule_timeout(_workflow_id, nil), do: :ok

  def schedule_timeout(workflow_id, deadline) do
    case Store.get_workflow(workflow_id) do
      {:ok, nil} ->
        :ok

      {:ok, workflow} ->
        {:ok, _job} = enqueue(workflow, scheduled_at: deadline)
        :ok

      _error ->
        :ok
    end
  end

  def cancel(workflow_id) do
    with {:ok, workflow} when not is_nil(workflow) <- Store.get_workflow(workflow_id),
         {:ok, cancelling} <- Store.update_workflow(workflow, :set_status, %{status: :cancelling}),
         {:ok, _job} <- enqueue(cancelling, []) do
      {:ok, cancelling}
    else
      {:ok, nil} -> {:error, :no_such_workflow}
      error -> error
    end
  end

  defp enqueue(workflow, options) do
    %{workflow_id: workflow.id}
    |> Worker.new(job_options(workflow.module, options))
    |> Oban.insert()
  end

  @default_lease_ms :timer.minutes(5)

  @doc """
  How long one attempt holds a workflow before another job may take it over.

  Read from the workflow itself first, falling back to `config :magma, lease_ms: ...` and then to
  five minutes. It has to outlast the longest attempt the workflow makes: a lease that lapses
  under a running attempt lets a second one start beside it, and one longer than it need be
  leaves a crashed attempt's workflow idle for the difference.
  """
  @spec lease_ms(module()) :: pos_integer()
  def lease_ms(module) do
    declared(module, :lease_ms) || Application.get_env(:magma, :lease_ms) || @default_lease_ms
  end

  defp declared(module, option) do
    if Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0) do
      Spark.Dsl.Extension.get_opt(module, [:magma], option, nil)
    end
  end

  # The magma section carries the queue and attempt policy, and an option at the call site
  # wins over it.
  #
  # A job already waiting its turn stands for every delivery made before it starts, so a burst
  # of signals against one workflow is one attempt rather than a crowd of them running over each
  # other. A job with a time to run is not one of those, and is always its own.
  defp job_options(module, options) do
    declared =
      if Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0) do
        [
          queue: Spark.Dsl.Extension.get_opt(module, [:magma], :queue, :default),
          max_attempts: Spark.Dsl.Extension.get_opt(module, [:magma], :max_attempts, 20)
        ]
      else
        []
      end

    declared
    |> Keyword.merge(
      Keyword.take(options, [:queue, :max_attempts, :priority, :schedule_in, :scheduled_at])
    )
    |> put_uniqueness()
  end

  defp put_uniqueness(options) do
    if Keyword.take(options, [:schedule_in, :scheduled_at]) == [] do
      Keyword.put(options, :unique, keys: [:workflow_id], states: [:available], period: :infinity)
    else
      options
    end
  end
end
