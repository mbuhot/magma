defmodule Magma.Notifier do
  @moduledoc false

  # Wakes a blocked `await` the moment its signal commits.
  #
  # It rides on Oban's notifier, so it reaches every node without magma taking a pubsub
  # dependency of its own. A missed message costs nothing: the step re-checks the store before
  # it halts, and a halted workflow is brought back by the resume job rather than by this.

  @channel :magma_signal

  @doc "Registers this process for a workflow's signal."
  @spec listen(String.t(), String.t()) :: :ok
  def listen(workflow_id, name) do
    Registry.register(__MODULE__, {workflow_id, name}, nil)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Tells anything blocked on a signal that it has landed."
  @spec broadcast(String.t(), String.t()) :: :ok
  def broadcast(workflow_id, name) do
    Registry.dispatch(__MODULE__, {workflow_id, name}, fn subscribers ->
      for {pid, _value} <- subscribers, do: send(pid, {:magma_signal, workflow_id, name})
    end)

    Oban.Notifier.notify(Oban, @channel, %{workflow_id: workflow_id, name: name})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  def child_spec(_options) do
    Registry.child_spec(keys: :duplicate, name: __MODULE__)
  end
end
