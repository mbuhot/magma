defmodule Agency.Sale.Conditions.Steps do
  @moduledoc "The steps the conditions of an exchanged contract are resolved by."

  alias Agency.Lender
  alias Agency.Sale
  alias Agency.Titles

  @doc "Whether the lender has decided the buyer's finance application yet."
  @spec finance_status(map(), map()) :: {:ok, map()} | :not_yet
  def finance_status(%{contract_id: contract_id}, _context) do
    case Lender.status(contract_id) do
      :approved -> {:ok, %{decision: :approved}}
      :declined -> {:ok, %{decision: :declined}}
      _still_assessing -> :not_yet
    end
  end

  @doc "Whether the title search has come back yet."
  @spec title_status(map(), map()) :: {:ok, map()} | :not_yet
  def title_status(%{contract_id: contract_id}, _context) do
    case Titles.status(contract_id) do
      :clear -> {:ok, %{decision: :satisfied}}
      :encumbered -> {:ok, %{decision: :failed}}
      _still_ordered -> :not_yet
    end
  end

  defmodule Resolve do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{contract_id: contract_id, response: response}, _context, options) do
      kind = Keyword.fetch!(options, :kind)
      status = status(kind, response)

      condition =
        contract_id
        |> Sale.conditions_for_contract!()
        |> Enum.find(&(&1.kind == kind))

      Sale.resolve_condition!(condition.id, %{status: status})

      {:ok, %{kind: kind, status: status}}
    end

    defp status(:finance, %{decision: :approved}), do: :satisfied
    defp status(:finance, %{decision: :declined}), do: :failed
    defp status(_kind, %{decision: :satisfied}), do: :satisfied
    defp status(_kind, %{decision: :failed}), do: :failed
  end

  defmodule Resolution do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(resolutions, _context, _options) do
      case Enum.find([:finance, :inspection, :title], &(resolutions[&1].status == :failed)) do
        nil -> {:ok, %{status: :satisfied, kind: nil}}
        kind -> {:ok, %{status: :failed, kind: kind}}
      end
    end
  end

  defmodule GoUnconditional do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{contract_id: contract_id}, _context, _options) do
      contract =
        Sale.go_unconditional!(contract_id, %{
          unconditional_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, %{contract_id: contract.id, unconditional_at: contract.unconditional_at}}
    end
  end

  defmodule Unconditional do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, %{outcome: :unconditional}}
  end

  defmodule Failed do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{resolution: resolution}, _context, _options) do
      {:ok, %{outcome: :condition_failed, kind: resolution.kind}}
    end
  end
end
