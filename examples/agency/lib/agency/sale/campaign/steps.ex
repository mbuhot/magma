defmodule Agency.Sale.Campaign.Steps do
  @moduledoc "The steps a marketing campaign over a listing is made of."

  defmodule Listing do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{agency_agreement_id: agency_agreement_id}, _context, _options) do
      agreement = Sale.get_agreement!(agency_agreement_id, load: [:property])

      {:ok,
       %{
         agency_agreement_id: agreement.id,
         address: agreement.property.address,
         sale_method: agreement.sale_method,
         guide_price: agreement.guide_price,
         term_end: agreement.term_end
       }}
    end
  end

  defmodule Launch do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{listing: listing}, _context, _options) do
      {:ok,
       %{
         address: listing.address,
         guide_price: listing.guide_price,
         launched_at: DateTime.utc_now() |> DateTime.truncate(:second)
       }}
    end
  end

  defmodule OpenAttempt do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{listing: listing}, _context, _options) do
      previous = Sale.attempts_for_agreement!(listing.agency_agreement_id)

      attempt =
        Sale.open_attempt!(%{
          agency_agreement_id: listing.agency_agreement_id,
          predecessor_id: previous |> List.last() |> then(&(&1 && &1.id)),
          generation: next_generation(previous),
          sale_method: listing.sale_method,
          opened_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, %{sale_attempt_id: attempt.id, generation: attempt.generation}}
    end

    defp next_generation([]), do: 1

    defp next_generation(previous),
      do: previous |> Enum.map(& &1.generation) |> Enum.max() |> Kernel.+(1)
  end

  defmodule Ended do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, options) do
      {:ok, %{outcome: Keyword.fetch!(options, :outcome)}}
    end
  end

  defmodule Reported do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{result: result}, _context, _options), do: {:ok, result}
  end
end
