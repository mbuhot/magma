defmodule Agency.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Agency.Sale
  alias Agency.Sale.Window

  using do
    quote do
      use Magma.Testing, repo: Agency.Repo

      import Agency.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Agency.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    :ok
  end

  @doc "A signed listing with its first attempt open, sold the given way."
  def a_listing(sale_method) do
    property =
      Sale.add_property!(%{
        address: "31 Rosebank Avenue",
        suburb: "Hawthorn",
        jurisdiction: :vic
      })

    agreement =
      Sale.sign_agreement!(%{
        property_id: property.id,
        vendor_name: "Priya Nair",
        agent_name: "Sam Okafor",
        appointment: :exclusive,
        term_start: ~D[2026-08-01],
        term_end: ~D[2026-11-01],
        commission_rate: Decimal.new("2.2"),
        commission_trigger: :on_settlement,
        sale_method: sale_method,
        guide_price: 900_000_00
      })

    Sale.open_attempt!(%{
      agency_agreement_id: agreement.id,
      generation: 1,
      opened_at: ~U[2026-08-05 00:00:00Z]
    })
  end

  @doc "A buyer on the listing's register."
  def a_buyer(attempt, name) do
    Sale.register_buyer!(%{agency_agreement_id: attempt.agency_agreement_id, name: name})
  end

  @doc "A live offer from a buyer, expiring at the end of the response window."
  def an_offer(attempt, buyer, amount) do
    Sale.make_offer!(%{
      sale_attempt_id: attempt.id,
      buyer_id: buyer.id,
      amount: amount,
      requested_conditions: [:finance],
      expires_at: Window.offer_expiry()
    })
  end

  @doc "Holds every wait long enough for its window to run out."
  def hold_waits_past_their_window do
    Application.put_env(:magma, :block_ms, 300)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:magma, :block_ms, 0) end)
  end
end
