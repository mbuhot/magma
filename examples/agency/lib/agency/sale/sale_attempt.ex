defmodule Agency.Sale.SaleAttempt do
  @moduledoc "One generation of the campaign to sell under an agency agreement."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("sale_attempts")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:generation, :integer, allow_nil?: false, public?: true)
    attribute(:sale_method, Agency.Sale.SaleMethod, allow_nil?: false, public?: true)

    attribute(:outcome, Agency.Sale.AttemptOutcome,
      allow_nil?: false,
      default: :running,
      public?: true
    )

    attribute(:opened_at, :utc_datetime, allow_nil?: false, public?: true)
    attribute(:closed_at, :utc_datetime, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:agency_agreement, Agency.Sale.AgencyAgreement, allow_nil?: false, public?: true)
    belongs_to(:predecessor, Agency.Sale.SaleAttempt, public?: true)
    has_many(:offers, Agency.Sale.Offer)
    has_one(:contract, Agency.Sale.Contract)
  end

  actions do
    defaults([:read])

    read :by_id do
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    create :open do
      accept([:agency_agreement_id, :predecessor_id, :generation, :sale_method, :opened_at])
    end

    update :close do
      accept([:outcome, :closed_at])
    end
  end
end
