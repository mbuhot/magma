defmodule Agency.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Agency.Sale
  alias Agency.Sale.AgencyAgreement
  alias Agency.Sale.SaleAttempt
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

  @doc "A signed agency agreement over a property, sold the given way."
  def a_signed_listing(overrides \\ %{}) do
    overrides = Map.new(overrides)

    property =
      Sale.add_property!(%{
        address: "31 Rosebank Avenue",
        suburb: "Hawthorn",
        jurisdiction: Map.get(overrides, :jurisdiction, :vic)
      })

    Sale.sign_agreement!(%{
      property_id: property.id,
      vendor_name: "Priya Nair",
      agent_name: "Sam Okafor",
      appointment: :exclusive,
      term_start: ~D[2026-08-01],
      term_end: ~D[2026-11-01],
      commission_rate: Decimal.new("2.2"),
      commission_trigger: Map.get(overrides, :commission_trigger, :on_settlement),
      sale_method: Map.get(overrides, :sale_method, :treaty),
      guide_price: Map.get(overrides, :guide_price, 900_000_00)
    })
  end

  @doc "A signed listing with its first attempt open, sold the given way."
  def a_listing(sale_method) do
    agreement = a_signed_listing(%{sale_method: sale_method})

    Sale.open_attempt!(%{
      agency_agreement_id: agreement.id,
      generation: 1,
      sale_method: sale_method,
      opened_at: ~U[2026-08-05 00:00:00Z]
    })
  end

  @doc "A buyer on the listing's register."
  def a_buyer(%AgencyAgreement{id: agency_agreement_id}, name) do
    Sale.register_buyer!(%{agency_agreement_id: agency_agreement_id, name: name})
  end

  def a_buyer(%SaleAttempt{agency_agreement_id: agency_agreement_id}, name) do
    Sale.register_buyer!(%{agency_agreement_id: agency_agreement_id, name: name})
  end

  @doc "A live offer from a buyer, expiring at the end of the response window."
  def an_offer(attempt, buyer, amount) do
    an_offer_expiring_at(attempt, buyer, amount, Window.offer_expiry())
  end

  @doc "A live offer from a buyer, expiring at the given instant."
  def an_offer_expiring_at(attempt, buyer, amount, expires_at) do
    Sale.make_offer!(%{
      sale_attempt_id: attempt.id,
      buyer_id: buyer.id,
      amount: amount,
      requested_conditions: [:finance],
      expires_at: expires_at
    })
  end

  @doc "The generation of the listing's campaign the agent is up to."
  def the_attempt(agreement, generation) do
    Sale.list_attempts!()
    |> Enum.filter(&(&1.agency_agreement_id == agreement.id and &1.generation == generation))
    |> List.first()
  end

  @doc "Runs everything the agency has ready, whichever desk it sits on."
  def run_agency do
    Enum.each(1..3, fn _pass ->
      Magma.Testing.run_workflows(queue: :compliance)
      Magma.Testing.run_workflows(queue: :sales)
    end)
  end

  @doc "Comes back to the agency's workflows once the given window has run out."
  def run_agency_after(window_ms) do
    Process.sleep(window_ms + 40)
    Magma.Testing.run_workflows(queue: :sales, with_scheduled: true)
    run_agency()
  end
end
