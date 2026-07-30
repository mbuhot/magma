defmodule Agency.Sale.Negotiation.Steps do
  @moduledoc "The steps one round of a negotiation is made of."

  alias Agency.Sale.Window

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
