defmodule Magma.Api do
  @moduledoc false

  alias Magma.Store
  alias Magma.Worker

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

    with {:ok, workflow} <- Store.start_workflow(attrs),
         {:ok, _job} <- enqueue(workflow, options) do
      {:ok, workflow}
    end
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

  def signal(workflow_id, name, payload) do
    Store.repo().transaction(fn ->
      with {:ok, signal} <- Store.deliver_signal(workflow_id, name, payload),
           :ok <- resume_if_parked(workflow_id, name) do
        signal
      else
        {:error, reason} -> Store.repo().rollback(reason)
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

  # The signal and the job that brings the workflow back commit together, so a crash on the
  # sending side cannot leave a parked workflow with nothing coming for it.
  defp resume_if_parked(workflow_id, name) do
    if Store.waiting_on?(workflow_id, name) do
      case Store.get_workflow(workflow_id) do
        {:ok, nil} -> :ok
        {:ok, workflow} -> with {:ok, _job} <- enqueue(workflow, []), do: :ok
        error -> error
      end
    else
      :ok
    end
  end

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

  # The magma section carries the queue and attempt policy, and an option at the call site
  # wins over it.
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

    Keyword.merge(
      declared,
      Keyword.take(options, [:queue, :max_attempts, :priority, :schedule_in, :scheduled_at])
    )
  end
end
