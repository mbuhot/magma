defmodule Agency.Lender do
  @moduledoc "The buyer's financier, stood in for."

  alias Agency.External

  @doc "Opens a finance application against a newly exchanged contract."
  @spec open!(String.t()) :: Ash.Resource.record()
  def open!(contract_id), do: External.open_finance_application!(%{contract_id: contract_id})

  @doc "Where the lender has got to with the given contract's application."
  @spec status(String.t()) :: Agency.External.FinanceStatus.t() | nil
  def status(contract_id) do
    case External.finance_application_for_contract(contract_id) do
      {:ok, application} -> application.status
      {:error, _reason} -> nil
    end
  end

  @doc "Moves the lender's decision on the given contract's application."
  @spec move!(String.t(), Agency.External.FinanceStatus.t()) :: Ash.Resource.record()
  def move!(contract_id, status) do
    {:ok, application} = External.finance_application_for_contract(contract_id)
    External.move_finance_application!(application.id, %{status: status})
  end
end
