defmodule Agency.Sale.Engagement do
  @moduledoc """
  The agency's engagement with a vendor, from the gate that lets the property be marketed to
  the sale that finally sticks.

  The compliance gate is cleared once and holds for the life of the agreement, so everything
  that can happen more than once — the marketing, the attempts beneath it — sits in the campaign
  the engagement dispatches. What the engagement answers with is whatever that campaign reached.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Agency.Sale.Engagement.Steps
  alias Agency.Sale.Jurisdiction

  magma do
    queue(:sales)
  end

  input(:agency_agreement_id)

  step :listing, Steps.Listing do
    argument(:agency_agreement_id, input(:agency_agreement_id))
  end

  dispatch :compliance_gate do
    workflow(&Jurisdiction.gate_for/2)
    queue(:compliance)
    argument(:jurisdiction, result(:listing, [:jurisdiction]))
    argument(:agency_agreement_id, input(:agency_agreement_id))
    inputs(fn arguments, _context -> Map.take(arguments, [:agency_agreement_id]) end)
  end

  dispatch :campaign do
    workflow(Agency.Sale.Campaign)
    queue(:sales)
    argument(:agency_agreement_id, input(:agency_agreement_id))
    wait_for(:compliance_gate)
  end

  step :engagement, Steps.Reported do
    argument(:result, result(:campaign))
  end

  return(:engagement)
end
