defmodule Agency.External.SettlementWorkspace do
  @moduledoc "One settlement workspace, held by PEXA against a contract."

  use Ash.Resource, domain: Agency.External, data_layer: AshPostgres.DataLayer

  postgres do
    table("settlement_workspaces")
    repo(Agency.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:contract_id, :uuid_v7, allow_nil?: false, public?: true)

    attribute(:status, Agency.External.SettlementStatus,
      allow_nil?: false,
      default: :booked,
      public?: true
    )

    timestamps()
  end

  identities do
    identity(:unique_contract, [:contract_id])
  end

  actions do
    defaults([:read])

    create :open do
      accept([:contract_id])
    end

    read :for_contract do
      argument(:contract_id, :uuid_v7, allow_nil?: false)
      get?(true)
      filter(expr(contract_id == ^arg(:contract_id)))
    end

    update :move do
      accept([:status])
    end
  end
end
