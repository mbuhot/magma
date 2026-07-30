defmodule Agency.Sale.Outcome do
  @moduledoc "The single shape every sale method and every negotiation answers with."

  @type via :: :hammer | :treaty | :treaty_after_pass_in

  @type t ::
          %{
            outcome: :accepted,
            buyer_id: String.t(),
            offer_id: String.t(),
            price: integer(),
            via: via()
          }
          | %{outcome: :no_sale, reason: :withdrawn | :lapsed | :passed_in_unsold}

  @doc "Terms the vendor and buyer agreed, for the caller to exchange on."
  @spec accepted(Ash.Resource.record(), via()) :: t()
  def accepted(offer, via) do
    %{
      outcome: :accepted,
      buyer_id: offer.buyer_id,
      offer_id: offer.id,
      price: offer.amount,
      via: via
    }
  end

  @doc "An attempt that ended without terms."
  @spec no_sale(:withdrawn | :lapsed | :passed_in_unsold) :: t()
  def no_sale(reason), do: %{outcome: :no_sale, reason: reason}

  @doc "Whether an outcome carries terms."
  @spec accepted?(t()) :: boolean()
  def accepted?(%{outcome: :accepted}), do: true
  def accepted?(%{outcome: :no_sale}), do: false

  defmodule Accepted do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{offer: offer}, _context, _options) do
      {:ok, Agency.Sale.Outcome.accepted(offer, :treaty)}
    end
  end

  defmodule NoSale do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, options) do
      {:ok, Agency.Sale.Outcome.no_sale(Keyword.fetch!(options, :reason))}
    end
  end

  defmodule Reported do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{outcome: outcome}, _context, _options), do: {:ok, outcome}
  end
end
