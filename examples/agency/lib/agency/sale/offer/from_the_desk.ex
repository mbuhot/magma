defmodule Agency.Sale.Offer.FromTheDesk do
  @moduledoc """
  Takes an offer the agent was given over the phone or across a table.

  The buyer is put on the register if this is the first the agency has heard of them, and the
  offer is written against whichever attempt the listing is presently running.
  """

  use Ash.Resource.Change

  alias Agency.Sale
  alias Agency.Sale.Window

  @impl true
  def change(changeset, _options, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      listing_id = Ash.Changeset.get_argument(changeset, :agency_agreement_id)
      name = Ash.Changeset.get_argument(changeset, :buyer_name)
      lender = Ash.Changeset.get_argument(changeset, :lender)
      dollars = Ash.Changeset.get_argument(changeset, :amount_dollars)

      attempt = listing_id |> Sale.attempts_for_agreement!() |> List.last()
      buyer = buyer(listing_id, name, lender)

      changeset
      |> Ash.Changeset.force_change_attribute(:sale_attempt_id, attempt.id)
      |> Ash.Changeset.force_change_attribute(:buyer_id, buyer.id)
      |> Ash.Changeset.force_change_attribute(:amount, dollars * 100)
      |> Ash.Changeset.force_change_attribute(:expires_at, Window.offer_expiry())
      |> Ash.Changeset.force_change_attribute(:requested_conditions, [
        :finance,
        :inspection,
        :title
      ])
    end)
  end

  defp buyer(listing_id, name, lender) do
    listing_id
    |> Sale.available_buyers!()
    |> Enum.find(&(&1.name == name))
    |> case do
      nil -> Sale.register_buyer!(%{agency_agreement_id: listing_id, name: name, lender: lender})
      buyer -> buyer
    end
  end
end
