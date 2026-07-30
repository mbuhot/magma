defmodule Agency.Sale.Jurisdiction.QLD.GateTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.Jurisdiction.QLD.Gate

  setup do
    property =
      Sale.add_property!(%{address: "9 Riverside Drive", suburb: "New Farm", jurisdiction: :qld})

    agreement =
      Sale.sign_agreement!(%{
        property_id: property.id,
        vendor_name: "Leilani Fa'amausili",
        agent_name: "Jordan Blake",
        appointment: :exclusive,
        term_start: ~D[2026-08-01],
        term_end: ~D[2026-11-01],
        commission_rate: Decimal.new("2.5"),
        commission_trigger: :on_settlement,
        sale_method: :auction,
        guide_price: 875_000_00
      })

    %{agreement: agreement}
  end

  test "the property cannot be marketed until the form 6, seller disclosure and title search all arrive",
       %{agreement: agreement} do
    {:ok, workflow} =
      Magma.start(Gate, %{agency_agreement_id: agreement.id}, queue: :compliance)

    run_workflows(queue: :compliance)

    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.form_6", %{})
    run_workflows(queue: :compliance)
    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.seller_disclosure", %{})
    run_workflows(queue: :compliance)
    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.title_search", %{})
    run_workflows(queue: :compliance)

    assert status(workflow) == :completed

    {:ok, reloaded} = Sale.get_agreement(agreement.id, load: [:compliance_documents])

    assert reloaded.compliance_documents |> Enum.map(& &1.kind) |> Enum.sort() == [
             :form_6,
             :seller_disclosure,
             :title_search
           ]
  end
end
