defmodule Agency.Sale.AgencyAgreement.SignListing do
  @moduledoc """
  Opens the property the agreement is for, and puts the agreement to work.

  Signing is the whole of taking a listing on: the property is recorded, the agreement is
  written against it, and the engagement that carries the sale starts on the way out.
  """

  use Ash.Resource.Change

  alias Agency.Sale
  alias Agency.Sale.Engagement

  @agent_name "Priya Chandra"
  @term_days 90

  @impl true
  def change(changeset, _options, _context) do
    changeset
    |> unless_given(:agent_name, @agent_name)
    |> unless_given(:appointment, :exclusive)
    |> unless_given(:commission_trigger, :on_settlement)
    |> unless_given(:term_start, Date.utc_today())
    |> unless_given(:term_end, Date.add(Date.utc_today(), @term_days))
    |> Ash.Changeset.before_action(&open_the_property/1)
    |> Ash.Changeset.after_transaction(&put_it_to_work/2)
  end

  defp open_the_property(changeset) do
    property =
      Sale.add_property!(%{
        address: Ash.Changeset.get_argument(changeset, :address),
        suburb: Ash.Changeset.get_argument(changeset, :suburb),
        jurisdiction: Ash.Changeset.get_argument(changeset, :jurisdiction)
      })

    dollars = Ash.Changeset.get_argument(changeset, :guide_price_dollars)

    changeset
    |> Ash.Changeset.force_change_attribute(:property_id, property.id)
    |> Ash.Changeset.force_change_attribute(:guide_price, dollars * 100)
  end

  defp unless_given(changeset, attribute, value) do
    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil -> Ash.Changeset.force_change_attribute(changeset, attribute, value)
      _given -> changeset
    end
  end

  defp put_it_to_work(_changeset, result) do
    with {:ok, agreement} <- result do
      {:ok, _workflow} = Engagement.start(agreement)
      {:ok, agreement}
    end
  end
end
