defmodule Agency.Sale.Commission do
  @moduledoc "The agent's entitlement earned by a sale attempt, and its discharge."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("commissions")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:amount, :integer, allow_nil?: false, public?: true)
    attribute(:accrued_at, :utc_datetime, allow_nil?: false, public?: true)

    attribute(:payable_on, Agency.Sale.CommissionTrigger, allow_nil?: false, public?: true)

    attribute(:disbursed_at, :utc_datetime, public?: true)
    attribute(:paid_from, :string, public?: true)

    attribute(:outcome, Agency.Sale.CommissionOutcome,
      allow_nil?: false,
      default: :accrued,
      public?: true
    )

    timestamps()
  end

  relationships do
    belongs_to(:sale_attempt, Agency.Sale.SaleAttempt, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read])

    read :for_attempt do
      argument(:sale_attempt_id, :uuid_v7, allow_nil?: false)
      filter(expr(sale_attempt_id == ^arg(:sale_attempt_id)))
    end

    create :accrue do
      accept([:sale_attempt_id, :amount, :accrued_at, :payable_on])
    end

    update :disburse do
      accept([:disbursed_at, :paid_from])
      change(set_attribute(:outcome, :disbursed))
    end

    update :write_back do
      accept([])
      change(set_attribute(:outcome, :written_back))
    end
  end
end
