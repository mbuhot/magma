defmodule Agency.Sale.Deposit do
  @moduledoc "The buyer's deposit held in trust against a contract."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("deposits")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:amount, :integer, allow_nil?: false, public?: true)
    attribute(:held_in, :string, allow_nil?: false, public?: true)

    attribute(:status, Agency.Sale.DepositStatus,
      allow_nil?: false,
      default: :held,
      public?: true
    )

    attribute(:forfeited_to, :string, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:contract, Agency.Sale.Contract, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read])

    create :collect do
      accept([:contract_id, :amount, :held_in])
    end

    update :settle_status do
      accept([:status, :forfeited_to])
    end
  end
end
