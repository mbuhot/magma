defmodule Payouts.Beneficiaries.Bridge do
  @moduledoc """
  Registering a Pakistani bank account as a Bridge recipient.

  Three checkpoints: read the account the customer gave us, tell Bridge about it, then store the
  reference Bridge gave back. The middle one declares an `undo`, so a registration that fails
  after Bridge has accepted the account withdraws it again rather than leaving a recipient
  standing that nothing refers to.

  Keyed on the beneficiary row, so registering the same account twice resumes the first run
  instead of opening a second recipient.
  """

  use Reactor, extensions: [Ash.Reactor, Magma.Dsl]

  alias Payouts.Beneficiaries.Bridge.Steps

  magma do
    queue(:onboarding)
    retention(:timer.hours(24 * 30))
  end

  input(:beneficiary_id)

  read_one :beneficiary, Payouts.Offramp.Beneficiary, :by_id do
    inputs(%{id: input(:beneficiary_id)})
    fail_on_not_found?(true)
  end

  read_one :onboarding, Payouts.Offramp.Onboarding, :for_rail do
    inputs(%{
      customer_id: result(:beneficiary, [:customer_id]),
      destination_currency: result(:beneficiary, [:destination_currency])
    })

    fail_on_not_found?(true)
  end

  step :registration, Steps.Register do
    argument(:beneficiary, result(:beneficiary))
    argument(:onboarding, result(:onboarding))
  end

  step :attach, Steps.Attach do
    argument(:beneficiary, result(:beneficiary))
    argument(:registration, result(:registration))
  end

  return(:attach)
end
