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

  defp enqueue(workflow, options) do
    %{workflow_id: workflow.id}
    |> Worker.new(Keyword.take(options, [:queue, :max_attempts, :priority, :schedule_in]))
    |> Oban.insert()
  end
end
