defmodule Agency.Sale.Engagement do
  @moduledoc """
  The agency's engagement with a vendor, from the gate that lets the property be marketed to
  the sale that finally sticks.

  The compliance gate and the campaign sit above the sale attempts, because they survive a
  contract falling over. What the engagement answers with is whatever the chain of attempts
  beneath it reached.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Agency.Sale.Engagement.Steps
  alias Agency.Sale.Jurisdiction
  alias Agency.Sale.Window

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

  step :campaign, Steps.LaunchCampaign do
    argument(:listing, result(:listing))
    wait_for(:compliance_gate)
  end

  await :campaign_outcome do
    signal("campaign.outcome")
    timeout(Window.agency_term())
    on_timeout(:return)
    wait_for(:campaign)
  end

  switch :engagement do
    on(result(:campaign_outcome))

    matches? &(&1 == :timeout) do
      step(:engagement, {Steps.Ended, outcome: :expired})
    end

    matches? &match?(%{decision: :withdrawn}, &1) do
      step(:engagement, {Steps.Ended, outcome: :withdrawn})
    end

    default do
      step :first_attempt, Steps.OpenFirstAttempt do
        argument(:listing, result(:listing))
      end

      dispatch :sale_attempt do
        workflow(Agency.Sale.Attempt)
        queue(:sales)
        argument(:sale_attempt_id, result(:first_attempt, [:sale_attempt_id]))
      end

      step :engagement, Steps.Reported do
        argument(:result, result(:sale_attempt))
      end
    end
  end

  return(:engagement)
end
