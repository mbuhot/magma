defmodule Payouts.Offramp.KycStatus do
  @moduledoc "How far a rail has got with a customer."

  use Ash.Type.Enum,
    values: [
      pending: "the submission is open and undecided",
      active: "the rail will pay this customer",
      resubmission_required: "the rail wants something else before it decides"
    ]
end
