defmodule Payouts.Offramp.Customer do
  @moduledoc """
  Someone with a balance to pay out.

  The balance is the sum of the customer's ledger entries. Nothing writes it, so nothing can
  make it disagree with the journal it comes from — which is why opening one is a deposit
  rather than a number set on the row.
  """

  use Ash.Resource, domain: Payouts.Offramp, data_layer: AshPostgres.DataLayer

  postgres do
    table("customers")
    repo(Payouts.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  relationships do
    has_many(:ledger_entries, Payouts.Offramp.LedgerEntry)
    has_many(:onboardings, Payouts.Offramp.Onboarding)
    has_many(:beneficiaries, Payouts.Offramp.Beneficiary)
  end

  aggregates do
    sum(:balance_cents, :ledger_entries, :amount_cents, default: 0)
  end

  actions do
    defaults([:read])

    read :with_standing do
      description("Every customer, with their balance and where they stand on each rail.")
      prepare(build(load: [:balance_cents, :onboardings, :beneficiaries]))
    end

    create :open do
      accept([:name])
      argument(:opening_balance_cents, :integer, allow_nil?: false, default: 0)

      change(Payouts.Offramp.Changes.PostOpeningBalance)
    end
  end
end
