defmodule Payouts.Offramp.Rejected do
  @moduledoc "Raised when the rail turns a transfer down, so the run unwinds and gives the money back."

  defexception [:transfer_id]

  @impl true
  def message(%{transfer_id: id}), do: "the provider rejected transfer #{id}"
end
