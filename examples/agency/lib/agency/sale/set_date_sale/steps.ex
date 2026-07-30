defmodule Agency.Sale.SetDateSale.Steps do
  @moduledoc "The steps a set date sale is made of."

  alias Agency.Sale
  alias Agency.Sale.Outcome

  defmodule OfferWindow do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{offer_deadline: offer_deadline}, _context, _options) do
      {:ok, %{closes_at: offer_deadline}}
    end
  end

  defmodule LiveOffers do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{sale_attempt_id: sale_attempt_id}, _context, _options) do
      offer_ids =
        sale_attempt_id
        |> Sale.live_offers_for_attempt!()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      {:ok, offer_ids}
    end
  end

  defmodule AcceptedTerms do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{negotiations: negotiations}, _context, _options) do
      {:ok, Enum.filter(negotiations, &Outcome.accepted?/1)}
    end
  end

  defmodule Missed do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{selection: :timeout}, _context, _options), do: {:ok, []}

    def run(%{accepted: accepted, selection: %{offer_id: selected_id}}, _context, _options) do
      missed_ids =
        accepted
        |> Enum.map(& &1.offer_id)
        |> Enum.reject(&(&1 == selected_id))

      Enum.each(missed_ids, &Sale.set_offer_status!(&1, %{status: :missed}))

      {:ok, missed_ids}
    end
  end

  defmodule Selected do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{selection: :timeout}, _context, _options), do: {:ok, Outcome.no_sale(:lapsed)}

    def run(%{accepted: accepted, selection: %{offer_id: selected_id}}, _context, _options) do
      case Enum.find(accepted, &(&1.offer_id == selected_id)) do
        nil -> {:error, "the vendor chose #{selected_id}, which no negotiation returned"}
        terms -> {:ok, terms}
      end
    end
  end
end
