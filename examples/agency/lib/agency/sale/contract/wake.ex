defmodule Agency.Sale.Contract.Wake do
  @moduledoc """
  Moves an outside system's state and brings the workflow back to find it moved.

  Nothing is signalled: these waits are polls, and a poll is answered by what the outside
  system says when the workflow looks again.

      change({Wake, move: {Agency.Lender, :move!}, to: :conditions})

  `decision` fixes the move where the caller has no say in it; otherwise the action's
  `:decision` argument carries it.
  """

  use Ash.Resource.Change

  alias Agency.Sale.Runs

  @impl true
  def change(changeset, options, _context) do
    Ash.Changeset.after_transaction(changeset, fn changeset, result ->
      with {:ok, contract} <- result do
        {module, function} = options[:move]
        decision = options[:decision] || changeset.arguments.decision

        apply(module, function, [contract.id, decision])

        :ok = Magma.wake(workflow_id(contract, options[:to]))

        {:ok, contract}
      end
    end)
  end

  defp workflow_id(contract, :conditions), do: Runs.conditions_of(listing_id(contract))
  defp workflow_id(contract, :attempt), do: Runs.attempt_id(listing_id(contract))

  defp listing_id(contract) do
    Agency.Sale.get_attempt!(contract.sale_attempt_id).agency_agreement_id
  end
end
