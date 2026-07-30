defmodule Agency.Sale.AgencyAgreement do
  @moduledoc "The vendor's engagement of an agent to sell a property."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("agency_agreements")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:vendor_name, :string, allow_nil?: false, public?: true)
    attribute(:agent_name, :string, allow_nil?: false, public?: true)

    attribute(:appointment, Agency.Sale.Appointment, allow_nil?: false, public?: true)

    attribute(:term_start, :date, allow_nil?: false, public?: true)
    attribute(:term_end, :date, allow_nil?: false, public?: true)
    attribute(:commission_rate, :decimal, allow_nil?: false, public?: true)

    attribute(:commission_trigger, Agency.Sale.CommissionTrigger,
      allow_nil?: false,
      public?: true
    )

    attribute(:sale_method, Agency.Sale.SaleMethod, allow_nil?: false, public?: true)
    attribute(:guide_price, :integer, allow_nil?: false, public?: true)

    timestamps()
  end

  relationships do
    belongs_to(:property, Agency.Sale.Property, allow_nil?: false, public?: true)
    has_many(:sale_attempts, Agency.Sale.SaleAttempt)
    has_many(:compliance_documents, Agency.Sale.ComplianceDocument)
    has_many(:buyers, Agency.Sale.Buyer)
  end

  actions do
    defaults([:read])

    read :by_id do
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    create :sign do
      accept([
        :property_id,
        :vendor_name,
        :agent_name,
        :appointment,
        :term_start,
        :term_end,
        :commission_rate,
        :commission_trigger,
        :sale_method,
        :guide_price
      ])
    end
  end
end
