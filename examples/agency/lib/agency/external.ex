defmodule Agency.External do
  @moduledoc """
  The third-party systems a sale depends on but the agency does not own.

  A lender, a title searching office and PEXA each hold their own queryable state, so the
  workflow polls them rather than waiting on a person to report. Kept apart from
  `Agency.Sale`, which is the agency's own record of the sale it is running.
  """

  use Ash.Domain

  resources do
    resource Agency.External.FinanceApplication do
      define(:open_finance_application, action: :open)
      define(:move_finance_application, action: :move, get_by: [:id])
      define(:finance_application_for_contract, action: :for_contract, args: [:contract_id])
      define(:list_finance_applications, action: :read)
    end

    resource Agency.External.TitleSearch do
      define(:open_title_search, action: :open)
      define(:move_title_search, action: :move, get_by: [:id])
      define(:title_search_for_contract, action: :for_contract, args: [:contract_id])
      define(:list_title_searches, action: :read)
    end

    resource Agency.External.SettlementWorkspace do
      define(:open_settlement_workspace, action: :open)
      define(:move_settlement_workspace, action: :move, get_by: [:id])

      define(:settlement_workspace_for_contract,
        action: :for_contract,
        args: [:contract_id]
      )

      define(:list_settlement_workspaces, action: :read)
    end
  end
end
