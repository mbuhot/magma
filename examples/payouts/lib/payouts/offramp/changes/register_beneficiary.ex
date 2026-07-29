defmodule Payouts.Offramp.Changes.RegisterBeneficiary do
  @moduledoc """
  Tells the rail about a recorded account, where the rail needs telling.

  A rail that pays the customer's own account has no registration workflow, so recording the
  row is the whole of it. The workflow is keyed on the row, so a registration that failed
  resumes rather than opening a second recipient.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, beneficiary ->
      with {:ok, _started} <- start(beneficiary) do
        {:ok, beneficiary}
      end
    end)
  end

  defp start(beneficiary) do
    case Payouts.Routing.beneficiary_for(beneficiary.destination_currency) do
      nil ->
        {:ok, beneficiary}

      workflow ->
        Magma.start(workflow, %{beneficiary_id: beneficiary.id},
          queue: :onboarding,
          workflow_id: Payouts.Offramp.Beneficiary.workflow_id(beneficiary.id)
        )
    end
  end
end
