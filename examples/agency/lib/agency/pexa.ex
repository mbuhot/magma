defmodule Agency.Pexa do
  @moduledoc "The PEXA settlement platform, stood in for."

  alias Agency.External

  @doc "Books a settlement workspace against a newly exchanged contract."
  @spec open!(String.t()) :: Ash.Resource.record()
  def open!(contract_id), do: External.open_settlement_workspace!(%{contract_id: contract_id})

  @doc "Where the workspace has got to for the given contract."
  @spec status(String.t()) :: Agency.External.SettlementStatus.t() | nil
  def status(contract_id) do
    case External.settlement_workspace_for_contract(contract_id) do
      {:ok, workspace} -> workspace.status
      {:error, _reason} -> nil
    end
  end

  @doc "Moves the given contract's workspace to how settlement went."
  @spec move!(String.t(), Agency.External.SettlementStatus.t()) :: Ash.Resource.record()
  def move!(contract_id, status) do
    {:ok, workspace} = External.settlement_workspace_for_contract(contract_id)
    External.move_settlement_workspace!(workspace.id, %{status: status})
  end
end
