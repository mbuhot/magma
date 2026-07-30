defmodule Agency.Sale.OfferTest do
  use Agency.DataCase, async: true

  alias Agency.Sale

  defp an_attempt do
    property =
      Sale.add_property!(%{
        address: "9 Banksia Court",
        suburb: "Leichhardt",
        jurisdiction: :nsw
      })

    agreement =
      Sale.sign_agreement!(%{
        property_id: property.id,
        vendor_name: "Priya Nair",
        agent_name: "Sam Okafor",
        appointment: :sole,
        term_start: ~D[2026-08-01],
        term_end: ~D[2026-11-01],
        commission_rate: Decimal.new("2.0"),
        commission_trigger: :on_unconditional,
        sale_method: :set_date,
        guide_price: 800_000_00
      })

    Sale.open_attempt!(%{
      agency_agreement_id: agreement.id,
      sale_method: :treaty,
      generation: 1,
      opened_at: ~U[2026-08-05 00:00:00Z]
    })
  end

  defp a_buyer(agreement_id) do
    Sale.register_buyer!(%{agency_agreement_id: agreement_id, name: "Jordan Lee"})
  end

  test "a countered offer replaces the one it followed, which is superseded" do
    attempt = an_attempt()
    buyer = a_buyer(attempt.agency_agreement_id)

    opening_offer =
      Sale.make_offer!(%{
        sale_attempt_id: attempt.id,
        buyer_id: buyer.id,
        amount: 780_000_00,
        requested_conditions: [:finance],
        expires_at: ~U[2026-08-10 00:00:00Z]
      })

    countered_offer =
      Sale.make_offer!(%{
        sale_attempt_id: attempt.id,
        buyer_id: buyer.id,
        amount: 800_000_00,
        requested_conditions: [:finance],
        expires_at: ~U[2026-08-12 00:00:00Z],
        supersedes_id: opening_offer.id
      })

    Sale.set_offer_status!(opening_offer.id, %{status: :superseded})

    reloaded_opening_offer = Sale.get_offer!(opening_offer.id)

    assert countered_offer.supersedes_id == opening_offer.id
    assert reloaded_opening_offer.status == :superseded
  end
end
