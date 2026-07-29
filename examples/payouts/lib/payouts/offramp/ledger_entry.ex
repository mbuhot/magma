defmodule Payouts.Offramp.LedgerEntry do
  @moduledoc """
  One movement against a customer's balance.

  Append-only. A movement that has to be taken back is taken back by posting its opposite.
  """

  use Ash.Resource, domain: Payouts.Offramp, data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table("ledger_entries")
    repo(Payouts.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:amount_cents, :integer, allow_nil?: false, public?: true)
    attribute(:reason, :string, allow_nil?: false, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:customer, Payouts.Offramp.Customer, allow_nil?: false, public?: true)
    belongs_to(:transfer, Payouts.Offramp.Transfer, public?: true)
  end

  actions do
    defaults([:read])

    read :for_transfer do
      argument(:transfer_id, :uuid_v7, allow_nil?: false)
      filter(expr(transfer_id == ^arg(:transfer_id)))
      prepare(build(sort: [:id]))
    end

    create :post do
      accept([:customer_id, :transfer_id, :amount_cents, :reason])
    end
  end
end
