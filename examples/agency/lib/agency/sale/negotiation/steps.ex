defmodule Agency.Sale.Negotiation.Steps do
  @moduledoc "The steps one round of a negotiation is made of."

  alias Agency.Sale.Window

  @doc "How long an offer's own response window still has to run."
  @spec response_deadline(map(), map()) :: pos_integer()
  def response_deadline(%{offer: offer}, _context), do: Window.ms_until(offer.expires_at)

  defmodule Decision do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{response: :timeout}, _context, _options), do: {:ok, :lapsed}

    def run(%{response: %{decision: decision}}, _context, _options)
        when decision in [:accept, :counter, :withdraw] do
      {:ok, decision}
    end
  end

  defmodule CounterExpiry do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, Window.offer_expiry()}
  end
end
