defmodule Agency.Sale.Jurisdiction.VIC.Gate do
  @moduledoc """
  VIC's pre-marketing gate: the vendor statement, the statement of information and the title
  search each arrive on their own signal before the property may be marketed.
  """

  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  alias Agency.Sale.ComplianceDocument
  alias Agency.Sale.Jurisdiction.Gate.Steps

  magma do
    queue(:compliance)
  end

  input(:agency_agreement_id)

  await :vendor_statement do
    signal("document.vendor_statement")
    timeout(:timer.hours(24 * 60))
  end

  create :vendor_statement_document, ComplianceDocument, :arrive do
    inputs(%{agency_agreement_id: input(:agency_agreement_id), kind: value(:vendor_statement)})
    wait_for(:vendor_statement)
  end

  await :statement_of_information do
    signal("document.statement_of_information")
    timeout(:timer.hours(24 * 60))
  end

  create :statement_of_information_document, ComplianceDocument, :arrive do
    inputs(%{
      agency_agreement_id: input(:agency_agreement_id),
      kind: value(:statement_of_information)
    })

    wait_for(:statement_of_information)
  end

  await :title_search do
    signal("document.title_search")
    timeout(:timer.hours(24 * 60))
  end

  create :title_search_document, ComplianceDocument, :arrive do
    inputs(%{agency_agreement_id: input(:agency_agreement_id), kind: value(:title_search)})
    wait_for(:title_search)
  end

  step :satisfied, Steps.Satisfied do
    wait_for([
      :vendor_statement_document,
      :statement_of_information_document,
      :title_search_document
    ])
  end

  return(:satisfied)
end
