defmodule Magma.DataCase do
  @moduledoc "A case template for tests that read and write magma's resources."

  use ExUnit.CaseTemplate

  using do
    quote do
      import Magma.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Magma.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc """
  The child failure inside a workflow's ending, however deeply it is wrapped.

  Takes a workflow id, or an error term to look inside directly.
  """
  def child_failure(workflow_id) when is_binary(workflow_id) do
    {:ok, %{error: error}} = Magma.fetch(workflow_id)
    dig(error)
  end

  def child_failure(error), do: dig(error)

  defp dig(%Magma.ChildError{} = child_error), do: child_error
  defp dig(%{errors: errors}) when is_list(errors), do: Enum.find_value(errors, &dig/1)
  defp dig(%{error: nested}), do: dig(nested)
  defp dig(_other), do: nil
end
