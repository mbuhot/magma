defmodule Agency.Titles do
  @moduledoc "The title searching office, stood in for."

  alias Agency.External

  @doc "Orders a title search against a newly exchanged contract."
  @spec open!(String.t()) :: Ash.Resource.record()
  def open!(contract_id), do: External.open_title_search!(%{contract_id: contract_id})

  @doc "Where the searching office has got to with the given contract's search."
  @spec status(String.t()) :: Agency.External.TitleStatus.t() | nil
  def status(contract_id) do
    case External.title_search_for_contract(contract_id) do
      {:ok, search} -> search.status
      {:error, _reason} -> nil
    end
  end

  @doc "Moves the search result on the given contract's title search."
  @spec move!(String.t(), Agency.External.TitleStatus.t()) :: Ash.Resource.record()
  def move!(contract_id, status) do
    {:ok, search} = External.title_search_for_contract(contract_id)
    External.move_title_search!(search.id, %{status: status})
  end
end
