defmodule Agency.Sale.AgencyAgreement do
  @moduledoc "The vendor's engagement of an agent to sell a property."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  alias Agency.Sale.Changes.Tell

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

    create :sign_listing do
      description("Takes a listing on: the property, the agreement over it, and the sale.")
      argument(:address, :string, allow_nil?: false)
      argument(:suburb, :string, allow_nil?: false)
      argument(:jurisdiction, Agency.Sale.Jurisdiction, allow_nil?: false)
      argument(:guide_price_dollars, :integer, allow_nil?: false)

      accept([
        :vendor_name,
        :agent_name,
        :appointment,
        :term_start,
        :term_end,
        :commission_rate,
        :commission_trigger,
        :sale_method
      ])

      change(Agency.Sale.AgencyAgreement.SignListing)
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

    update :hand_over_document do
      description("Tells the compliance gate that one of its documents has arrived.")
      require_atomic?(false)
      argument(:kind, :string, allow_nil?: false)

      change({Tell, to: :gate, signal: {"document.", :kind}})
    end

    update :launch_campaign do
      description("Takes the property to market.")
      require_atomic?(false)

      change({Tell, to: :campaign, signal: "campaign.outcome", payload: %{decision: :proceed}})
    end

    update :withdraw_listing do
      description("Takes the property off the market for good.")
      require_atomic?(false)

      change({Tell, to: :campaign, signal: "campaign.outcome", payload: %{decision: :withdrawn}})
    end

    update :re_approach do
      description("Calls a named underbidder back after a contract fell over.")
      require_atomic?(false)
      argument(:buyer_id, :uuid_v7, allow_nil?: false)

      change(
        {Tell,
         to: :attempt,
         signal: "succession.decision",
         payload: %{decision: :re_approach},
         from_arguments: [:buyer_id]}
      )
    end

    update :relaunch_campaign do
      description("Puts the property back on the market as a fresh campaign.")
      require_atomic?(false)

      change({Tell, to: :attempt, signal: "succession.decision", payload: %{decision: :relaunch}})
    end

    update :close_offers do
      description("Closes the window a set date sale invited offers in.")
      require_atomic?(false)

      change({Tell, to: {:method, :set_date}, signal: "set_date.offers_close"})
    end

    update :select_offer do
      description("Carries the vendor's choice of offer to the sale.")
      require_atomic?(false)
      argument(:offer_id, :uuid_v7, allow_nil?: false)

      change(
        {Tell,
         to: {:method, :set_date},
         signal: "set_date.vendor_selection",
         from_arguments: [:offer_id]}
      )
    end

    update :pass_in do
      description("Passes the property in, which sends the agent back to negotiating.")
      require_atomic?(false)

      change(
        {Tell, to: {:method, :auction}, signal: "auction.hammer", payload: %{result: :passed_in}}
      )
    end

    update :sell_under_the_hammer do
      description("Drops the hammer on the offer standing when the auction ends.")
      require_atomic?(false)

      change(
        {Tell,
         to: {:method, :auction},
         signal: "auction.hammer",
         payload: {Agency.Sale.AgencyAgreement.Hammer, :payload}}
      )
    end

    update :rescind do
      description("Records that a buyer rescinded inside the cooling off window.")
      require_atomic?(false)
      argument(:buyer_id, :uuid_v7, allow_nil?: false)

      change({Tell, to: :attempt, signal: "cooling_off.rescission", from_arguments: [:buyer_id]})
    end

    update :resolve_inspection do
      description("Records how the building inspection came back.")
      require_atomic?(false)
      argument(:decision, :atom, allow_nil?: false, constraints: [one_of: [:satisfied, :failed]])

      change({Tell, to: :conditions, signal: "condition.inspection", from_arguments: [:decision]})
    end
  end
end
