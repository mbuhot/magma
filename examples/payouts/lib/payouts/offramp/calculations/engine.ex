defmodule Payouts.Offramp.Calculations.Engine do
  @moduledoc """
  What magma has recorded for a transfer's payout.

  The workflow's id is derived from the transfer's, so none of this is stored on the row —
  it is read from the engine whenever it is loaded.
  """

  use Ash.Resource.Calculation

  alias Payouts.Offramp.Payout

  @impl true
  def load(_query, _opts, _context), do: [:id]

  @impl true
  def calculate(transfers, opts, _context) do
    part = Keyword.fetch!(opts, :part)

    Enum.map(transfers, &value(part, Payout.workflow_id(&1.id)))
  end

  defp value(:workflow, workflow_id), do: fetch(workflow_id)
  defp value(:tape, workflow_id), do: tape(workflow_id)
  defp value(:waiting_on, workflow_id), do: Magma.Store.waiters(workflow_id)
  defp value(:rail, workflow_id), do: workflow_id |> rail_id() |> fetch()
  defp value(:rail_tape, workflow_id), do: workflow_id |> rail_id() |> tape()

  defp rail_id(workflow_id), do: Magma.child_id(workflow_id, :rail)

  defp tape(workflow_id), do: workflow_id |> Magma.steps() |> Enum.sort_by(& &1.id)

  defp fetch(workflow_id) do
    case Magma.fetch(workflow_id) do
      {:ok, workflow} -> workflow
      _error -> nil
    end
  end
end
