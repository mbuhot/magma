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
      term_end: Map.get(overrides, :term_end, ~D[2026-11-01]),
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
    agreement.id
    |> Sale.attempts_for_agreement!()
    |> Enum.find(&(&1.generation == generation))
  end

  @doc "The contract the given generation exchanged."
  def the_contract(attempt), do: attempt.id |> Sale.contracts_for_attempt!() |> List.first()

  @doc "The deposit held against the contract the given generation exchanged."
  def the_deposit(attempt) do
    attempt |> the_contract() |> Map.fetch!(:id) |> Sale.deposits_for_contract!() |> List.first()
  end

  @doc "The commission the given generation earned."
  def the_commission(attempt), do: attempt.id |> Sale.commissions_for_attempt!() |> List.first()

  @doc "The offers the given generation is holding, dearest first."
  def the_offers(attempt), do: Sale.offers_for_attempt!(attempt.id)

  @doc "The buyers the given generation has a live offer from."
  def the_live_buyer_ids(attempt) do
    attempt.id |> Sale.live_offers_for_attempt!() |> Enum.map(& &1.buyer_id)
  end

  @doc "Where the given buyer stands on the listing's register."
  def the_register_status(buyer), do: Sale.get_buyer!(buyer.id).register_status

  @doc "The conditions imposed on the contract the given generation exchanged."
  def the_conditions(attempt) do
    attempt |> the_contract() |> Map.fetch!(:id) |> Sale.conditions_for_contract!()
  end

  @doc "Whether the workflow is presently held up on the given wait."
  def waiting?(%{id: workflow_id}, name), do: waiting?(workflow_id, name)

  def waiting?(workflow_id, name) when is_binary(workflow_id) do
    Agency.Magma.Waiter
    |> Ash.read!()
    |> Enum.any?(&(&1.workflow_id == workflow_id and &1.name == name))
  end

  @doc "Runs everything the agency has ready, whichever desk it sits on."
  def run_agency do
    Enum.each(1..3, fn _pass ->
      Magma.Testing.run_workflows(queue: :compliance)
      Magma.Testing.run_workflows(queue: :sales)
    end)
  end

  @doc """
  Comes back to the agency's workflows once the given window has run out.

  Only the timeout due at this moment is forced; anything it goes on to dispatch is picked up
  by the ordinary pass after, so a poll newly started in the same beat gets to wait its turn
  rather than being forced to check again before any real time has passed.
  """
  def run_agency_after(window_ms) do
    Process.sleep(window_ms + 40)
    Magma.Testing.run_workflows(queue: :sales, with_scheduled: true, with_recursion: false)
    run_agency()
  end

  @doc "Forces a workflow parked on a poll to check the external system again, without waiting out its interval."
  def nudge(workflow_id) do
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow_id}})
    run_agency()
  end
end
