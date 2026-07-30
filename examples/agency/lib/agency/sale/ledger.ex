defmodule Agency.Sale.Ledger do
  @moduledoc """
  What an agency agreement has earned, given back, and left with the vendor.

  A listing can carry several attempts, each with its own commission and deposit, so the
  standing position is the sum across all of them: what was disbursed, what was written back
  when a sale fell over, and what a rescinding buyer forfeited.
  """

  @type totals :: %{paid: integer(), written_back: integer(), forfeited: integer()}

  @doc "The position across every commission and deposit a listing has raised."
  @spec totals([Ash.Resource.record()], [Ash.Resource.record()]) :: totals()
  def totals(commissions, deposits) do
    %{
      paid: summed(commissions, :disbursed),
      written_back: summed(commissions, :written_back),
      forfeited: deposits |> Enum.map(&(&1.forfeited_amount || 0)) |> Enum.sum()
    }
  end

  defp summed(commissions, outcome) do
    commissions
    |> Enum.filter(&(&1.outcome == outcome))
    |> Enum.map(& &1.amount)
    |> Enum.sum()
  end
end
