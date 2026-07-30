defmodule Agency.Sale.Buyer do
  @moduledoc "Someone interested in the property, tracked across every attempt."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("buyers")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:conveyancer, :string, public?: true)
    attribute(:lender, :string, public?: true)

    attribute(:register_status, Agency.Sale.RegisterStatus,
      allow_nil?: false,
      default: :available,
      public?: true
    )

    timestamps()
  end

  relationships do
    belongs_to(:agency_agreement, Agency.Sale.AgencyAgreement, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read])

    read :by_id do
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    read :available_for_agreement do
      argument(:agency_agreement_id, :uuid_v7, allow_nil?: false)

      filter(
        expr(agency_agreement_id == ^arg(:agency_agreement_id) and register_status == :available)
      )

      prepare(build(sort: [inserted_at: :asc]))
    end

    create :register do
      accept([:agency_agreement_id, :name, :conveyancer, :lender])
    end

    update :set_register_status do
      accept([:register_status])
    end
  end
end
