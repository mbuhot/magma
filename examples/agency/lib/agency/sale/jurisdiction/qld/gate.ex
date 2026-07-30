defmodule Agency.Sale.Jurisdiction.QLD.Gate do
  @moduledoc """
  QLD's pre-marketing gate: the form 6 appointment, the seller disclosure statement and the
  title search each arrive on their own signal before the property may be marketed.
  """

  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  alias Agency.Sale.ComplianceDocument
  alias Agency.Sale.Jurisdiction.Gate.Steps

  magma do
    queue(:compliance)
  end

  input(:agency_agreement_id)

  await :form_6 do
    signal("document.form_6")
    timeout(:timer.hours(24 * 60))
  end

  create :form_6_document, ComplianceDocument, :arrive do
    inputs(%{agency_agreement_id: input(:agency_agreement_id), kind: value(:form_6)})
    wait_for(:form_6)
  end

  await :seller_disclosure do
    signal("document.seller_disclosure")
    timeout(:timer.hours(24 * 60))
  end

  create :seller_disclosure_document, ComplianceDocument, :arrive do
    inputs(%{agency_agreement_id: input(:agency_agreement_id), kind: value(:seller_disclosure)})
    wait_for(:seller_disclosure)
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
      :form_6_document,
      :seller_disclosure_document,
      :title_search_document
    ])
  end

  return(:satisfied)
end
