defmodule Agency.Sale.Engagement.Steps do
  @moduledoc "The steps the agency's engagement above a sale attempt is made of."

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
         jurisdiction: agreement.property.jurisdiction,
         address: agreement.property.address,
         sale_method: agreement.sale_method,
         guide_price: agreement.guide_price,
         term_end: agreement.term_end
       }}
    end
  end

  defmodule LaunchCampaign do
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

  defmodule OpenFirstAttempt do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{listing: listing}, _context, _options) do
      attempt =
        Sale.open_attempt!(%{
          agency_agreement_id: listing.agency_agreement_id,
          generation: 1,
          sale_method: listing.sale_method,
          opened_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, %{sale_attempt_id: attempt.id, generation: attempt.generation}}
    end
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
