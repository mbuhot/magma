defmodule Magma.Test.Effects do
  @moduledoc "Counts what each step actually did, so a test can prove nothing ran twice."

  def start_link do
    Agent.start_link(fn -> %{order: []} end, name: __MODULE__)
  end

  def reset, do: Agent.update(__MODULE__, fn _state -> %{order: []} end)

  def record(name) do
    Agent.update(__MODULE__, fn state ->
      state
      |> Map.update(name, 1, fn count -> count + 1 end)
      |> Map.update(:order, [name], &(&1 ++ [name]))
    end)
  end

  def order, do: Agent.get(__MODULE__, &Map.get(&1, :order, []))

  def fail_undo(name), do: Agent.update(__MODULE__, &Map.put(&1, {:fail_undo, name}, true))

  def undo_should_fail?(name), do: Agent.get(__MODULE__, &Map.get(&1, {:fail_undo, name}, false))

  def count(name), do: Agent.get(__MODULE__, &Map.get(&1, name, 0))

  def counts, do: Agent.get(__MODULE__, & &1)

  def fail_after(name, count), do: Agent.update(__MODULE__, &Map.put(&1, {:fail, name}, count))

  def should_fail?(name) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, {:fail, name}) do
        nil -> {false, state}
        0 -> {false, state}
        remaining -> {true, Map.put(state, {:fail, name}, remaining - 1)}
      end
    end)
  end
end
