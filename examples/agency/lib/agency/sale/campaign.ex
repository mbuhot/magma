defmodule Agency.Sale.Campaign do
  @moduledoc """
  A marketing campaign over a listing, and the generation of attempts it opens.

  The campaign sits beneath the engagement and above the sale attempts, because a property can
  go to market more than once under the one agreement while the compliance gate is cleared only
  the once. An attempt whose chain ends with the agent choosing fresh marketing answers with
  `:relaunch`, and the campaign runs again as its own child.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Agency.Sale.Campaign.Steps
  alias Agency.Sale.Window

  magma do
    queue(:sales)
  end

  input(:agency_agreement_id)

  step :listing, Steps.Listing do
    argument(:agency_agreement_id, input(:agency_agreement_id))
  end

  step :launch, Steps.Launch do
    argument(:listing, result(:listing))
  end

  await :campaign_outcome do
    signal("campaign.outcome")
    timeout(Window.agency_term())
    on_timeout(:return)
    wait_for(:launch)
  end

  switch :campaign do
    on(result(:campaign_outcome))

    matches? &(&1 == :timeout) do
      step(:campaign, {Steps.Ended, outcome: :expired})
    end

    matches? &match?(%{decision: :withdrawn}, &1) do
      step(:campaign, {Steps.Ended, outcome: :withdrawn})
    end

    default do
      step :attempt, Steps.OpenAttempt do
        argument(:listing, result(:listing))
      end

      dispatch :sale_attempt do
        workflow(Agency.Sale.Attempt)
        queue(:sales)
        argument(:sale_attempt_id, result(:attempt, [:sale_attempt_id]))
      end

      switch :continuation do
        on(result(:sale_attempt, [:outcome]))

        matches? &(&1 == :relaunch) do
          dispatch :relaunch do
            workflow(Agency.Sale.Campaign)
            queue(:sales)
            argument(:agency_agreement_id, input(:agency_agreement_id))
          end

          step :continuation, Steps.Reported do
            argument(:result, result(:relaunch))
          end
        end

        default do
          step :continuation, Steps.Reported do
            argument(:result, result(:sale_attempt))
          end
        end
      end

      step :campaign, Steps.Reported do
        argument(:result, result(:continuation))
      end
    end
  end

  return(:campaign)
end
