defmodule Magma.Test.Effects do
  @moduledoc "Counts what each step actually did, so a test can prove nothing ran twice."

  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def reset, do: Agent.update(__MODULE__, fn _state -> %{} end)

  def record(name) do
    Agent.update(__MODULE__, &Map.update(&1, name, 1, fn count -> count + 1 end))
  end

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
