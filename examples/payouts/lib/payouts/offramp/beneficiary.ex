defmodule Payouts.Offramp.Beneficiary do
  @moduledoc """
  A bank account a rail will pay on the customer's behalf.

  Only rails that pay a third party need one. A rail that pays the customer's own account
  has no beneficiary workflow in config, and no row is ever registered for it.
  """

  use Ash.Resource, domain: Payouts.Offramp, data_layer: AshPostgres.DataLayer

  require Ash.Query

  @doc "The workflow id an account's registration with its rail runs under."
  @spec workflow_id(String.t()) :: String.t()
  def workflow_id(beneficiary_id), do: Magma.child_id(beneficiary_id, :registration)

  postgres do
    table("beneficiaries")
    repo(Payouts.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:destination_currency, :string, allow_nil?: false, public?: true)
    attribute(:account_number, :string, allow_nil?: false, public?: true)
    attribute(:bank_code, :string, allow_nil?: false, public?: true)

    attribute(:status, Payouts.Offramp.BeneficiaryStatus,
      allow_nil?: false,
      default: :recorded,
      public?: true
    )

    attribute(:provider_ref, :string, public?: true)
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

    read :by_id do
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

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

    create :record do
      accept([:customer_id, :destination_currency, :account_number, :bank_code])
      upsert?(true)
      upsert_identity(:one_per_rail)
    end

    create :register do
      description("Records the account and registers it with the rail, where the rail wants one.")
      accept([:customer_id, :destination_currency, :account_number, :bank_code])
      upsert?(true)
      upsert_identity(:one_per_rail)

      change(Payouts.Offramp.Changes.RegisterBeneficiary)
    end

    update :attach_ref do
      accept([:provider_ref])
      change(set_attribute(:status, :registered))
      require_atomic?(false)
    end

    update :release_ref do
      change(set_attribute(:provider_ref, nil))
      change(set_attribute(:status, :recorded))
      require_atomic?(false)
    end
  end
end
