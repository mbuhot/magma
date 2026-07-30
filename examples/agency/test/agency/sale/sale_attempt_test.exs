defmodule Agency.Sale.SaleAttemptTest do
  use Agency.DataCase, async: true

  alias Agency.Sale

  defp an_agreement do
    property =
      Sale.add_property!(%{
        address: "4 Fig Lane",
        suburb: "Marrickville",
        jurisdiction: :nsw
      })

    Sale.sign_agreement!(%{
      property_id: property.id,
      vendor_name: "Priya Nair",
      agent_name: "Sam Okafor",
      appointment: :exclusive,
      term_start: ~D[2026-08-01],
      term_end: ~D[2026-11-01],
      commission_rate: Decimal.new("2.2"),
      commission_trigger: :on_settlement,
      sale_method: :treaty,
      guide_price: 900_000_00
    })
  end

  test "a later generation reads back to the attempt it followed" do
    agreement = an_agreement()

    first_attempt =
      Sale.open_attempt!(%{
        agency_agreement_id: agreement.id,
        sale_method: :treaty,
        generation: 1,
        opened_at: ~U[2026-08-05 00:00:00Z]
      })

    Sale.close_attempt!(first_attempt.id, %{
      outcome: :rescinded,
      closed_at: ~U[2026-08-20 00:00:00Z]
    })

    second_attempt =
      Sale.open_attempt!(%{
        agency_agreement_id: agreement.id,
        sale_method: :treaty,
        predecessor_id: first_attempt.id,
        generation: 2,
        opened_at: ~U[2026-08-21 00:00:00Z]
      })

    assert second_attempt.predecessor_id == first_attempt.id
    assert second_attempt.generation == 2
  end
end
