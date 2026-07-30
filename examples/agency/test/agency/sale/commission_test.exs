defmodule Agency.Sale.CommissionTest do
  use Agency.DataCase, async: true

  alias Agency.Sale

  defp an_attempt do
    property =
      Sale.add_property!(%{
        address: "27 Myrtle Avenue",
        suburb: "Balmain",
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
        commission_trigger: :on_unconditional,
        sale_method: :auction,
        guide_price: 1_100_000_00
      })

    Sale.open_attempt!(%{
      agency_agreement_id: agreement.id,
      generation: 1,
      opened_at: ~U[2026-08-05 00:00:00Z]
    })
  end

  test "accrual and disbursement are recorded as separate events" do
    attempt = an_attempt()

    commission =
      Sale.accrue_commission!(%{
        sale_attempt_id: attempt.id,
        amount: 24_200_00,
        accrued_at: ~U[2026-09-01 00:00:00Z],
        payable_on: :on_unconditional
      })

    assert commission.outcome == :accrued
    assert commission.disbursed_at == nil

    disbursed_commission =
      Sale.disburse_commission!(commission.id, %{
        disbursed_at: ~U[2026-09-10 00:00:00Z],
        paid_from: "trust account"
      })

    assert disbursed_commission.accrued_at == commission.accrued_at
    assert disbursed_commission.disbursed_at == ~U[2026-09-10 00:00:00Z]
    assert disbursed_commission.outcome == :disbursed
  end
end
