defmodule Agency.Sale.Jurisdiction.VIC.GateTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.Jurisdiction.VIC.Gate

  setup do
    property =
      Sale.add_property!(%{address: "4 Bourke Lane", suburb: "Fitzroy", jurisdiction: :vic})

    agreement =
      Sale.sign_agreement!(%{
        property_id: property.id,
        vendor_name: "Marcus Webb",
        agent_name: "Chloe Ng",
        appointment: :exclusive,
        term_start: ~D[2026-08-01],
        term_end: ~D[2026-11-01],
        commission_rate: Decimal.new("2.0"),
        commission_trigger: :on_settlement,
        sale_method: :auction,
        guide_price: 980_000_00
      })

    %{agreement: agreement}
  end

  test "the property cannot be marketed until the vendor statement, statement of information and title search all arrive",
       %{agreement: agreement} do
    {:ok, workflow} =
      Magma.start(Gate, %{agency_agreement_id: agreement.id}, queue: :compliance)

    run_workflows(queue: :compliance)

    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.vendor_statement", %{})
    run_workflows(queue: :compliance)
    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.statement_of_information", %{})
    run_workflows(queue: :compliance)
    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.title_search", %{})
    run_workflows(queue: :compliance)

    assert status(workflow) == :completed

    {:ok, reloaded} = Sale.get_agreement(agreement.id, load: [:compliance_documents])

    assert reloaded.compliance_documents |> Enum.map(& &1.kind) |> Enum.sort() == [
             :statement_of_information,
             :title_search,
             :vendor_statement
           ]

    assert Enum.all?(reloaded.compliance_documents, &(&1.received_at != nil))
  end
end
