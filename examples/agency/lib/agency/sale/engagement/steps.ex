defmodule Agency.Sale.Engagement.Steps do
  @moduledoc "The steps the agency's engagement above a campaign is made of."

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
         jurisdiction: agreement.property.jurisdiction
       }}
    end
  end

  defmodule Reported do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{result: result}, _context, _options), do: {:ok, result}
  end
end
