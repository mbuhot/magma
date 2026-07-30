defmodule Agency.Sale.SetDateSale.Steps do
  @moduledoc "The steps a set date sale is made of."

  alias Agency.Sale
  alias Agency.Sale.Outcome
  alias Agency.Sale.Window

  @doc "How long a set date sale still has before it stops taking offers."
  @spec offers_close_deadline(map(), map()) :: pos_integer()
  def offers_close_deadline(%{offer_deadline: offer_deadline}, _context) do
    Window.ms_until(offer_deadline)
  end

  @doc "How long the vendor can sit on the offers still live, bounded by the soonest to expire."
  @spec vendor_selection_deadline(map(), map()) :: pos_integer()
  def vendor_selection_deadline(%{accepted: accepted}, _context) do
    accepted
    |> Enum.map(&Sale.get_offer!(&1.offer_id).expires_at)
    |> Enum.min(DateTime)
    |> Window.ms_until()
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
