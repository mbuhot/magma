defmodule Agency.Sale.Auction.Steps do
  @moduledoc "The steps an auction is made of."

  alias Agency.Sale

  defmodule ReserveSet do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{sale_attempt_id: sale_attempt_id, reserve: reserve}, _context, _options) do
      {:ok, %{sale_attempt_id: sale_attempt_id, reserve: reserve}}
    end
  end

  defmodule HighestBidder do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{sale_attempt_id: sale_attempt_id}, _context, _options) do
      {:ok, sale_attempt_id |> Sale.live_offers_for_attempt!() |> List.first()}
    end
  end

  defmodule Verdict do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{hammer: %{result: :sold}}, _context, _options), do: {:ok, :sold}

    def run(%{hammer: %{result: :passed_in}, highest_bidder: nil}, _context, _options) do
      {:ok, :unsold}
    end

    def run(%{hammer: %{result: :passed_in}}, _context, _options), do: {:ok, :treaty}
  end

  defmodule Sold do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{hammer: hammer}, _context, _options) do
      {:ok,
       %{
         outcome: :accepted,
         buyer_id: hammer.buyer_id,
         offer_id: hammer.offer_id,
         price: hammer.price,
         via: :hammer
       }}
    end
  end

  defmodule AfterPassIn do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{outcome: %{outcome: :accepted} = outcome}, _context, _options) do
      {:ok, %{outcome | via: :treaty_after_pass_in}}
    end

    def run(%{outcome: outcome}, _context, _options), do: {:ok, outcome}
  end
end
