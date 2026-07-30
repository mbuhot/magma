defmodule Agency.Sale.Property do
  @moduledoc "A piece of real estate, independent of any agreement to sell it."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("properties")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:address, :string, allow_nil?: false, public?: true)
    attribute(:suburb, :string, allow_nil?: false, public?: true)

    attribute(:jurisdiction, Agency.Sale.Jurisdiction, allow_nil?: false, public?: true)

    timestamps()
  end

  relationships do
    has_many(:agency_agreements, Agency.Sale.AgencyAgreement)
  end

  actions do
    defaults([:read])

    read :by_id do
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    create :add do
      accept([:address, :suburb, :jurisdiction])
    end
  end
end
