defmodule Payouts.Onboarding.Meridian do
  @moduledoc """
  Meridian's KYC: open the customer record, issue the account they are paid into.

  Two steps against Bridge's nine, no documents and no submission to resume into. The rail
  config is the only thing that has to know the difference.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Payouts.Onboarding.Meridian.Steps

  magma do
    queue(:onboarding)
    retention(:timer.hours(24 * 30))
  end

  input(:onboarding_id)

  step :onboarding, Payouts.Onboarding.Bridge.Steps.Load do
    argument(:onboarding_id, input(:onboarding_id))
  end

  step :account, Steps.CreateAccount do
    argument(:onboarding, result(:onboarding))
  end

  step :identity, Steps.IssueIdentity do
    argument(:account, result(:account))
    argument(:onboarding, result(:onboarding))
  end

  return(:identity)
end
