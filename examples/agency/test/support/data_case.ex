defmodule Agency.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Agency.Sale
  alias Agency.Sale.AgencyAgreement
  alias Agency.Sale.SaleAttempt
  alias Agency.Sale.Window
  alias Magma.Store

  @desk_turns 25

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

  @doc "Every generation the listing has opened, in the order the agent reached them."
  def the_generations(agreement) do
    agreement.id |> Sale.attempts_for_agreement!() |> Enum.map(& &1.generation) |> Enum.sort()
  end

  @doc "The generation of the listing's campaign the agent is up to."
  def the_attempt(agreement, generation) do
    agreement.id
    |> Sale.attempts_for_agreement!()
    |> Enum.find(&(&1.generation == generation))
    |> case do
      nil -> raise missing(agreement, generation)
      attempt -> attempt
    end
  end

  @doc "The contract the given generation exchanged."
  def the_contract(attempt) do
    case attempt.id |> Sale.contracts_for_attempt!() |> List.first() do
      nil -> raise unexchanged(attempt)
      contract -> contract
    end
  end

  @doc "The deposit held against the contract the given generation exchanged."
  def the_deposit(attempt) do
    case attempt |> the_contract() |> Map.fetch!(:id) |> Sale.deposits_for_contract!() do
      [] -> raise "#{describe(attempt)} has exchanged a contract that holds no deposit"
      [deposit | _rest] -> deposit
    end
  end

  @doc "The commission the given generation earned."
  def the_commission(attempt) do
    case attempt.id |> Sale.commissions_for_attempt!() |> List.first() do
      nil -> raise "#{describe(attempt)} has earned no commission"
      commission -> commission
    end
  end

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

  @doc """
  Runs everything the agency has ready, whichever desk it sits on, until both desks are clear.

  A workflow finishing on one desk is work arriving on the other, so the desks are worked in
  turn until a turn finds nothing left to run.
  """
  def run_agency do
    work_both_desks(@desk_turns)
  end

  @doc """
  Runs a wait's window out and brings its workflow back to find the window gone.

  The window a wait was parked with is deployment policy, so it is moved rather than waited
  out: the wait keeps its identity and the workflow reaches its timeout branch on the next
  attempt of it.
  """
  def let_the_wait_lapse(workflow, name) when is_map(workflow) do
    let_the_wait_lapse(workflow.id, name)
  end

  def let_the_wait_lapse(workflow_id, name) when is_binary(workflow_id) do
    case Store.waiter(workflow_id, name) do
      nil ->
        raise "#{workflow_id} is not parked on #{name}, it holds #{parked_on(workflow_id)}"

      %{kind: :poll} ->
        raise "#{name} is a poll, which never runs out; move its external state and nudge instead"

      %{kind: :signal} ->
        {:ok, _lapsed} = Store.park(workflow_id, name, :signal, a_moment_ago())
        nudge(workflow_id)
        assert_the_wait_is_over(workflow_id, name)
    end
  end

  @doc "Forces a workflow parked on a poll to check the external system again, without waiting out its interval."
  def nudge(workflow_id) do
    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow_id}})
    run_agency()
  end

  defp work_both_desks(0) do
    raise """
    the agency was still finding work to run after #{@desk_turns} turns over its desks.

    Either a workflow is dispatching without ever settling, or #{@desk_turns} turns is no
    longer enough to carry a chain from one desk to the other.
    """
  end

  defp work_both_desks(turns_left) do
    compliance = Magma.Testing.run_workflows(queue: :compliance)
    sales = Magma.Testing.run_workflows(queue: :sales)

    if clear?(compliance) and clear?(sales) do
      :ok
    else
      work_both_desks(turns_left - 1)
    end
  end

  defp clear?(drained), do: drained |> Map.values() |> Enum.sum() == 0

  defp a_moment_ago, do: DateTime.add(DateTime.utc_now(), -1, :second)

  defp assert_the_wait_is_over(workflow_id, name) do
    if Store.waiter(workflow_id, name) do
      raise "#{workflow_id} is still parked on #{name} after its window ran out"
    end

    :ok
  end

  defp parked_on(workflow_id) do
    case Store.waiters(workflow_id) do
      [] -> "nothing, and stands at #{inspect(Magma.Testing.status(workflow_id))}"
      waiters -> Enum.map_join(waiters, ", ", & &1.name)
    end
  end

  defp missing(agreement, generation) do
    "this listing has no generation #{generation}, only #{inspect(the_generations(agreement))}"
  end

  defp unexchanged(attempt) do
    "#{describe(attempt)} has exchanged no contract"
  end

  defp describe(attempt) do
    reloaded = Sale.get_attempt!(attempt.id)

    "generation #{reloaded.generation}, which stands at #{inspect(reloaded.outcome)},"
  end
end
