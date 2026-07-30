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

    read :for_attempt do
      argument(:sale_attempt_id, :uuid_v7, allow_nil?: false)
      filter(expr(sale_attempt_id == ^arg(:sale_attempt_id)))
    end

    create :exchange do
      accept([:sale_attempt_id, :buyer_id, :price, :exchanged_at, :settlement_date])
    end

    update :go_unconditional do
      accept([:unconditional_at])
    end

    update :record_finance do
      description("Moves the lender's answer on the buyer's finance, and lets the sale notice.")
      require_atomic?(false)
      argument(:decision, :atom, allow_nil?: false, constraints: [one_of: [:approved, :declined]])

      change({Agency.Sale.Contract.Wake, move: {Agency.Lender, :move!}, to: :conditions})
    end

    update :record_title do
      description("Moves what the title office found, and lets the sale notice.")
      require_atomic?(false)
      argument(:decision, :atom, allow_nil?: false, constraints: [one_of: [:clear, :encumbered]])

      change({Agency.Sale.Contract.Wake, move: {Agency.Titles, :move!}, to: :conditions})
    end

    update :settle do
      description("Settles the contract in PEXA, and lets the sale notice.")
      require_atomic?(false)

      change(
        {Agency.Sale.Contract.Wake, move: {Agency.Pexa, :move!}, decision: :settled, to: :attempt}
      )
    end

    update :buyer_defaults do
      description("Records that the buyer failed to settle, and lets the sale notice.")
      require_atomic?(false)

      change(
        {Agency.Sale.Contract.Wake,
         move: {Agency.Pexa, :move!}, decision: :defaulted, to: :attempt}
      )
    end
  end
end
