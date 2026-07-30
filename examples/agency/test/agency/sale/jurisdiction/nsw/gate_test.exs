defmodule Agency.Sale.Jurisdiction.NSW.GateTest do
  use Agency.DataCase, async: false

  alias Agency.Sale
  alias Agency.Sale.Jurisdiction.NSW.Gate

  setup do
    property =
      Sale.add_property!(%{address: "12 Wattle Street", suburb: "Newtown", jurisdiction: :nsw})

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

    %{agreement: agreement}
  end

  test "the property cannot be marketed until the solicitor's contract and prescribed documents all arrive",
       %{agreement: agreement} do
    {:ok, workflow} =
      Magma.start(Gate, %{agency_agreement_id: agreement.id}, queue: :compliance)

    run_workflows(queue: :compliance)

    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.contract", %{})
    run_workflows(queue: :compliance)
    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.title_search", %{})
    run_workflows(queue: :compliance)
    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.drainage_diagram", %{})
    run_workflows(queue: :compliance)
    assert status(workflow) == :waiting

    Magma.signal(workflow.id, "document.planning_certificate", %{})
    run_workflows(queue: :compliance)

    assert status(workflow) == :completed

    {:ok, reloaded} = Sale.get_agreement(agreement.id, load: [:compliance_documents])

    assert reloaded.compliance_documents |> Enum.map(& &1.kind) |> Enum.sort() == [
             :contract,
             :drainage_diagram,
             :planning_certificate,
             :title_search
           ]

    assert Enum.all?(reloaded.compliance_documents, &(&1.received_at != nil))
  end
end
