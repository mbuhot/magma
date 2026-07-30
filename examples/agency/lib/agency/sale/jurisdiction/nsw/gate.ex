defmodule Agency.Sale.Jurisdiction.NSW.Gate do
  @moduledoc """
  NSW's pre-marketing gate: the property cannot be marketed until the vendor's solicitor has
  the contract prepared with the title search, drainage diagram and planning certificate
  attached.

  Each document waits on its own signal, so one solicitor's delay never blocks another's.
  """

  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  alias Agency.Sale.ComplianceDocument
  alias Agency.Sale.Jurisdiction.Gate.Steps

  magma do
    queue(:compliance)
  end

  input(:agency_agreement_id)

  await :contract do
    signal("document.contract")
    timeout(:timer.hours(24 * 60))
  end

  create :contract_document, ComplianceDocument, :require do
    inputs(%{agency_agreement_id: input(:agency_agreement_id), kind: value(:contract)})
    wait_for(:contract)
  end

  await :title_search do
    signal("document.title_search")
    timeout(:timer.hours(24 * 60))
  end

  create :title_search_document, ComplianceDocument, :require do
    inputs(%{agency_agreement_id: input(:agency_agreement_id), kind: value(:title_search)})
    wait_for(:title_search)
  end

  await :drainage_diagram do
    signal("document.drainage_diagram")
    timeout(:timer.hours(24 * 60))
  end

  create :drainage_diagram_document, ComplianceDocument, :require do
    inputs(%{agency_agreement_id: input(:agency_agreement_id), kind: value(:drainage_diagram)})
    wait_for(:drainage_diagram)
  end

  await :planning_certificate do
    signal("document.planning_certificate")
    timeout(:timer.hours(24 * 60))
  end

  create :planning_certificate_document, ComplianceDocument, :require do
    inputs(%{
      agency_agreement_id: input(:agency_agreement_id),
      kind: value(:planning_certificate)
    })

    wait_for(:planning_certificate)
  end

  step :satisfied, Steps.Satisfied do
    wait_for([
      :contract_document,
      :title_search_document,
      :drainage_diagram_document,
      :planning_certificate_document
    ])
  end

  return(:satisfied)
end
