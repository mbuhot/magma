defmodule Agency.Sale.Condition do
  @moduledoc "One condition a contract is subject to."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("conditions")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:kind, Agency.Sale.ConditionKind, allow_nil?: false, public?: true)
    attribute(:due_date, :date, allow_nil?: false, public?: true)

    attribute(:status, Agency.Sale.ConditionStatus,
      allow_nil?: false,
      default: :pending,
      public?: true
    )

    timestamps()
  end

  relationships do
    belongs_to(:contract, Agency.Sale.Contract, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read])

    create :impose do
      accept([:contract_id, :kind, :due_date])
    end

    update :resolve do
      accept([:status])
    end
  end
end
