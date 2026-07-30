defmodule Agency.Sale.AgencyAgreementTest do
  use Agency.DataCase, async: true

  alias Agency.Sale

  test "an agency agreement carries the property it was signed against" do
    property =
      Sale.add_property!(%{
        address: "12 Wattle Street",
        suburb: "Newtown",
        jurisdiction: :nsw
      })

    agreement =
      Sale.sign_agreement!(%{
        property_id: property.id,
        vendor_name: "Priya Nair",
        agent_name: "Sam Okafor",
        appointment: :exclusive,
        term_start: ~D[2026-08-01],
        term_end: ~D[2026-11-01],
        commission_rate: Decimal.new("2.2"),
        commission_trigger: :on_settlement,
        sale_method: :auction,
        guide_price: 1_250_000_00
      })

    assert agreement.property_id == property.id
    assert agreement.sale_method == :auction
  end
end
