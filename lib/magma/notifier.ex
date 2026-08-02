defmodule Magma.Notifier do
  @moduledoc false

  # Wakes a blocked `await` the moment its signal commits.
  #
  # It rides on Oban's notifier, so it reaches every node without magma taking a pubsub
  # dependency of its own. A missed message costs nothing: the step re-checks the store before
  # it halts, and a halted workflow is brought back by the resume job rather than by this.

  @channel :magma_signal

  @doc "Registers this process for a workflow's signal, and for the run giving up."
  @spec listen(String.t(), String.t()) :: :ok
  def listen(workflow_id, name) do
    Registry.register(__MODULE__, {workflow_id, name}, nil)
    Registry.register(__MODULE__, {workflow_id, :halting}, nil)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Tells everything blocked on a workflow's signals that the run is halting.

  A wait blocks to catch a signal that lands in the next few seconds and spare the run a replay.
  Once another step has halted, there is no run left to spare: the attempt is over, and a signal
  arriving now brings the workflow back on a job of its own. So the wait gives up its window
  rather than holding the halt open for the length of it.
  """
  @spec halting(String.t()) :: :ok
  def halting(workflow_id) do
    Registry.dispatch(__MODULE__, {workflow_id, :halting}, fn subscribers ->
      for {pid, _value} <- subscribers, do: send(pid, {:magma_halting, workflow_id})
    end)

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
