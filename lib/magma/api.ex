defmodule Magma.Api do
  @moduledoc false

  alias Magma.Store
  alias Magma.Worker

  def start(module, inputs, options) do
    attrs = %{
      module: module,
      inputs: inputs,
      actor: options[:actor],
      tenant: options[:tenant]
    }

    with {:ok, workflow} <- Store.start_workflow(attrs),
         {:ok, _job} <- enqueue(workflow, options) do
      {:ok, workflow}
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
    |> Worker.new(Keyword.take(options, [:queue, :max_attempts, :priority, :schedule_in]))
    |> Oban.insert()
  end
end
