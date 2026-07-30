defmodule Agency.Sale.Offer do
  @moduledoc "A buyer's proposed terms within a negotiation, and its place in that chain."

  use Ash.Resource, domain: Agency.Sale, data_layer: AshPostgres.DataLayer

  postgres do
    table("offers")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:amount, :integer, allow_nil?: false, public?: true)

    attribute(:requested_conditions, {:array, Agency.Sale.ConditionKind},
      allow_nil?: false,
      default: [],
      public?: true
    )

    attribute(:expires_at, :utc_datetime, allow_nil?: false, public?: true)

    attribute(:status, Agency.Sale.OfferStatus,
      allow_nil?: false,
      default: :live,
      public?: true
    )

    timestamps()
  end

  relationships do
    belongs_to(:sale_attempt, Agency.Sale.SaleAttempt, allow_nil?: false, public?: true)
    belongs_to(:buyer, Agency.Sale.Buyer, allow_nil?: false, public?: true)
    belongs_to(:supersedes, Agency.Sale.Offer, public?: true)
  end

  actions do
    defaults([:read])

    read :by_id do
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    read :for_attempt do
      argument(:sale_attempt_id, :uuid_v7, allow_nil?: false)
      filter(expr(sale_attempt_id == ^arg(:sale_attempt_id)))
      prepare(build(sort: [amount: :desc]))
    end

    read :live_for_attempt do
      argument(:sale_attempt_id, :uuid_v7, allow_nil?: false)
      filter(expr(sale_attempt_id == ^arg(:sale_attempt_id) and status == :live))
      prepare(build(sort: [amount: :desc]))
    end

    create :make do
      accept([
        :sale_attempt_id,
        :buyer_id,
        :amount,
        :requested_conditions,
        :expires_at,
        :supersedes_id
      ])
    end

    create :receive do
      description("Records an offer the agent was given, registering the buyer if they are new.")
      argument(:agency_agreement_id, :uuid_v7, allow_nil?: false)
      argument(:buyer_name, :string, allow_nil?: false)
      argument(:lender, :string)
      argument(:amount_dollars, :integer, allow_nil?: false)

      change(Agency.Sale.Offer.FromTheDesk)
    end

    update :set_status do
      accept([:status])
    end

    update :respond do
      description("Answers the buyer: accept the offer, counter it, or walk away.")
      require_atomic?(false)

      argument(:decision, :atom,
        allow_nil?: false,
        constraints: [one_of: [:accept, :counter, :withdraw]]
      )

      argument(:amount, :integer)

      change(
        {Agency.Sale.Changes.Tell,
         to: :negotiation, signal: "negotiation.response", from_arguments: [:decision, :amount]}
      )
    end
  end
end
