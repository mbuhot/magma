defmodule Payouts.Offramp.Onboarding do
  @moduledoc "Where a customer stands with one rail's KYC."

  use Ash.Resource, domain: Payouts.Offramp, data_layer: AshPostgres.DataLayer

  require Ash.Query

  @doc "The workflow id a customer's KYC on one rail runs under."
  @spec workflow_id(String.t()) :: String.t()
  def workflow_id(onboarding_id), do: Magma.child_id(onboarding_id, :kyc)

  postgres do
    table("onboardings")
    repo(Payouts.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:destination_currency, :string, allow_nil?: false, public?: true)

    attribute(:status, Payouts.Offramp.KycStatus,
      allow_nil?: false,
      default: :pending,
      public?: true
    )

    attribute(:account_ref, :string, public?: true)
    attribute(:identity_ref, :string, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:customer, Payouts.Offramp.Customer, allow_nil?: false, public?: true)
  end

  identities do
    identity(:one_per_rail, [:customer_id, :destination_currency])
  end

  actions do
    defaults([:read, :destroy])

    read :for_rail do
      get?(true)
      argument(:customer_id, :uuid_v7, allow_nil?: false)
      argument(:destination_currency, :string, allow_nil?: false)

      filter(
        expr(
          customer_id == ^arg(:customer_id) and
            destination_currency == ^arg(:destination_currency)
        )
      )
    end

    create :begin do
      accept([:customer_id, :destination_currency])
      upsert?(true)
      upsert_identity(:one_per_rail)
    end

    create :start_kyc do
      description("Opens the record and runs the KYC workflow the currency's rail asks for.")
      accept([:customer_id, :destination_currency])
      upsert?(true)
      upsert_identity(:one_per_rail)

      change(Payouts.Offramp.Changes.RunOnboarding)
    end

    update :record_progress do
      accept([:status, :account_ref, :identity_ref])
      require_atomic?(false)
    end
  end
end
