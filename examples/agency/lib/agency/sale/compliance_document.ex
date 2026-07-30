defmodule Agency.Sale.ComplianceDocument do
  @moduledoc "A document a jurisdiction's pre-marketing gate requires, and when it arrived."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("compliance_documents")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:kind, Agency.Sale.DocumentKind, allow_nil?: false, public?: true)
    attribute(:received_at, :utc_datetime, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:agency_agreement, Agency.Sale.AgencyAgreement, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read])

    create :require do
      accept([:agency_agreement_id, :kind])
    end

    update :receive do
      accept([:received_at])
    end
  end
end
