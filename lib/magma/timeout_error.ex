defmodule Magma.TimeoutError do
  @moduledoc "Raised when a wait reaches its deadline without the signal arriving."

  defexception [:signal]

  @impl true
  def message(%{signal: signal}), do: "waiting for #{inspect(signal)} reached its deadline"
end
