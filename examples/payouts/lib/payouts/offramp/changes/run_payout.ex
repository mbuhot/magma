defmodule Payouts.Offramp.Changes.RunPayout do
  @moduledoc """
  Starts the payout that carries a transfer out.

  Its id is derived from the transfer, so asking for the same payout twice starts one run.

  Started inside the transaction that writes the transfer, so the transfer, the workflow row
  and the job that runs it all commit together.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, transfer ->
      with {:ok, _workflow} <- Payouts.Offramp.Payout.start(transfer.id) do
        {:ok, transfer}
      end
    end)
  end
end
