defmodule Payouts.Offramp.Changes.RunOnboarding do
  @moduledoc """
  Runs the KYC workflow the currency's rail asks for.

  Started inside the transaction that writes the row, so an onboarding cannot exist with
  nothing coming to carry it out. The job is invisible to Oban until that transaction commits.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, onboarding ->
      with {:ok, _workflow} <- start(onboarding) do
        {:ok, onboarding}
      end
    end)
  end

  defp start(onboarding) do
    workflow = Payouts.Routing.onboarding_for(%{onboarding: onboarding}, %{})

    Magma.start(workflow, %{onboarding_id: onboarding.id},
      queue: :onboarding,
      workflow_id: Payouts.Offramp.Onboarding.workflow_id(onboarding.id)
    )
  end
end
