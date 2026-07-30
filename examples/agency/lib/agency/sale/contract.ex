defmodule Agency.Sale.Contract do
  @moduledoc "The exchanged contract for one sale attempt."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("contracts")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:price, :integer, allow_nil?: false, public?: true)
    attribute(:exchanged_at, :utc_datetime, allow_nil?: false, public?: true)
    attribute(:unconditional_at, :utc_datetime, public?: true)
    attribute(:settlement_date, :date, allow_nil?: false, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:sale_attempt, Agency.Sale.SaleAttempt, allow_nil?: false, public?: true)
    belongs_to(:buyer, Agency.Sale.Buyer, allow_nil?: false, public?: true)
    has_many(:conditions, Agency.Sale.Condition)
    has_one(:deposit, Agency.Sale.Deposit)
  end

  actions do
    defaults([:read])

    create :exchange do
      accept([:sale_attempt_id, :buyer_id, :price, :exchanged_at, :settlement_date])
    end

    update :go_unconditional do
      accept([:unconditional_at])
    end
  end
end
