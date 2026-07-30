defmodule Magma.ChildError do
  @moduledoc """
  How a dispatched child's failure reaches the workflow that dispatched it.

  `workflow_id` and `module` name the child. `error` is the child's own error, reachable for a
  caller that wants to match on it. A chain of dispatches nests one of these inside the next, so
  the outermost message reads down to the cause.
  """

  defexception [:workflow_id, :module, :error]

  @type t :: %__MODULE__{workflow_id: String.t(), module: module() | nil, error: term()}

  @impl true
  def message(%__MODULE__{workflow_id: workflow_id, module: module, error: error}) do
    "child workflow #{inspect(module)} #{workflow_id} failed: #{describe(error)}"
  end

  defp describe(error) when is_exception(error), do: Exception.message(error)
  defp describe(error), do: inspect(error)
end
