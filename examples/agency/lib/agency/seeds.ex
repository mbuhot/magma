defmodule Agency.Seeds do
  @moduledoc """
  Four listings, each a genuinely running workflow parked at a deliberately different wait, so
  the branching the agency example argues for is visible the moment the app opens.

  Every listing is reached the same way any real listing is: sign the agreement, start the
  engagement, hand over the jurisdiction's documents, launch the campaign, then drive the sale
  attempt as far as its story calls for. Nothing here writes a row that imitates a state a
  workflow never reached. The Manly listing ends where a contract falling over leaves an agent:
  waiting on which underbidder to call back.
  """

  alias Agency.Sale
  alias Magma.Testing

  @agent_name "Priya Chandra"

  @tables ~w(
    magma_signals magma_waiters magma_checkpoints magma_workflows
    finance_applications settlement_workspaces title_searches
    commissions deposits conditions contracts offers sale_attempts
    compliance_documents buyers agency_agreements properties
    oban_jobs
  )

  @doc "Wipes every table this example owns, so a seed or a test run starts from nothing."
  @spec reset!() :: :ok
  def reset! do
    {:ok, _result} =
      Ecto.Adapters.SQL.query(
        Agency.Repo,
        "TRUNCATE TABLE #{Enum.join(@tables, ", ")} RESTART IDENTITY CASCADE"
      )

    :ok
  end

  @doc "Seeds the four listings the sales desk and console are built to show off."
  @spec seed!() :: :ok
  def seed! do
    seed_kurraba()
    seed_rialto()
    seed_ardoyne()
    seed_marine()

    :ok
  end

  defp seed_kurraba do
    agreement =
      sign_listing(%{
        address: "14 Kurraba Road",
        suburb: "Neutral Bay",
        jurisdiction: :nsw,
        vendor_name: "J. & M. Halloran",
        sale_method: :set_date,
        commission_rate: Decimal.new("2.2"),
        commission_trigger: :on_settlement,
        guide_price: 1_350_000_00
      })

    danforth = register_buyer(agreement, "Danforth", "Whitlock Mutual")
    osei_bright = register_buyer(agreement, "Osei-Bright", "Cardinia Bank")
    verhoeven = register_buyer(agreement, "Verhoeven", "cash")

    workflow = engage(agreement)
    hand_over_documents(workflow.id, :nsw)
    proceed(workflow.id)

    attempt_id = first_attempt_id(workflow.id)

    make_offer(attempt_id, danforth, 1_385_000_00)
    make_offer(attempt_id, osei_bright, 1_420_000_00)
    make_offer(attempt_id, verhoeven, 1_362_500_00)
  end

  defp seed_rialto do
    agreement =
      sign_listing(%{
        address: "8 Rialto Street",
        suburb: "Fitzroy North",
        jurisdiction: :vic,
        vendor_name: "D. Ferrante",
        sale_method: :auction,
        commission_rate: Decimal.new("2.0"),
        commission_trigger: :on_settlement,
        guide_price: 1_200_000_00
      })

    nakagawa = register_buyer(agreement, "Nakagawa", "Boroondara Bank")
    ellery = register_buyer(agreement, "Ellery", "cash")

    workflow = engage(agreement)
    hand_over_documents(workflow.id, :vic)
    proceed(workflow.id)

    attempt_id = first_attempt_id(workflow.id)

    make_offer(attempt_id, nakagawa, 1_205_000_00)
    make_offer(attempt_id, ellery, 1_178_000_00)
  end

  defp seed_ardoyne do
    agreement =
      sign_listing(%{
        address: "22 Ardoyne Road",
        suburb: "Corinda",
        jurisdiction: :qld,
        vendor_name: "T. Okonkwo",
        sale_method: :treaty,
        commission_rate: Decimal.new("2.5"),
        commission_trigger: :on_unconditional,
        guide_price: 890_000_00
      })

    whitlam = register_buyer(agreement, "Whitlam", "Sunstate Building Society")

    workflow = engage(agreement)
    hand_over_documents(workflow.id, :qld)

    attempt_id = open_first_attempt(workflow.id)
    make_offer(attempt_id, whitlam, 905_000_00)
    run_agency()

    sale_attempt = Magma.child_id(campaign_of(workflow.id), :sale_attempt)
    treaty_negotiation = Magma.child_id(Magma.child_id(sale_attempt, :treaty), :negotiation)

    {:ok, _signal} =
      Magma.signal(treaty_negotiation, "negotiation.response", %{decision: :accept})

    run_agency()
  end

  defp seed_marine do
    agreement =
      sign_listing(%{
        address: "51 Marine Parade",
        suburb: "Manly",
        jurisdiction: :nsw,
        vendor_name: "S. Achterberg",
        sale_method: :set_date,
        commission_rate: Decimal.new("2.2"),
        commission_trigger: :on_settlement,
        guide_price: 2_400_000_00
      })

    rasmussen = register_buyer(agreement, "Rasmussen", "Northern Trust")
    pettifer = register_buyer(agreement, "Pettifer", "Meridian Bank")
    choudhury = register_buyer(agreement, "Choudhury", "cash")

    workflow = engage(agreement)
    hand_over_documents(workflow.id, :nsw)
    proceed(workflow.id)

    first_generation = Magma.child_id(campaign_of(workflow.id), :sale_attempt)
    attempt_id = first_attempt_id(workflow.id)

    rasmussen_offer = make_offer(attempt_id, rasmussen, 2_480_000_00)
    make_offer(attempt_id, pettifer, 2_445_000_00)
    make_offer(attempt_id, choudhury, 2_412_000_00)

    set_date = Magma.child_id(first_generation, :set_date)
    {:ok, _signal} = Magma.signal(set_date, "set_date.offers_close", %{})
    run_agency()

    set_date
    |> live_offer_ids()
    |> Enum.with_index()
    |> Enum.each(fn {_offer_id, index} ->
      negotiation =
        Magma.child_id(set_date, {Reactor.Step.Map, :negotiations, :negotiation, index})

      {:ok, _signal} = Magma.signal(negotiation, "negotiation.response", %{decision: :accept})
      run_agency()
    end)

    {:ok, _signal} =
      Magma.signal(set_date, "set_date.vendor_selection", %{offer_id: rasmussen_offer.id})

    run_agency()

    {:ok, _signal} =
      Magma.signal(first_generation, "cooling_off.rescission", %{buyer_id: rasmussen.id})

    run_agency()
  end

  defp sign_listing(attrs) do
    property =
      Sale.add_property!(%{
        address: attrs.address,
        suburb: attrs.suburb,
        jurisdiction: attrs.jurisdiction
      })

    Sale.sign_agreement!(%{
      property_id: property.id,
      vendor_name: attrs.vendor_name,
      agent_name: @agent_name,
      appointment: :exclusive,
      term_start: Date.utc_today(),
      term_end: Date.add(Date.utc_today(), 90),
      commission_rate: attrs.commission_rate,
      commission_trigger: attrs.commission_trigger,
      sale_method: attrs.sale_method,
      guide_price: attrs.guide_price
    })
  end

  defp register_buyer(agreement, name, lender) do
    Sale.register_buyer!(%{agency_agreement_id: agreement.id, name: name, lender: lender})
  end

  defp make_offer(sale_attempt_id, buyer, amount) do
    Sale.make_offer!(%{
      sale_attempt_id: sale_attempt_id,
      buyer_id: buyer.id,
      amount: amount,
      requested_conditions: [:finance, :inspection, :title],
      expires_at: Agency.Sale.Window.offer_expiry()
    })
  end

  defp engage(agreement) do
    {:ok, workflow} =
      Magma.start(Agency.Sale.Engagement, %{agency_agreement_id: agreement.id}, queue: :sales)

    run_agency()

    workflow
  end

  defp campaign_of(workflow_id), do: Magma.child_id(workflow_id, :campaign)

  defp hand_over_documents(workflow_id, jurisdiction) do
    gate = Magma.child_id(workflow_id, :compliance_gate)

    jurisdiction
    |> compliance_documents()
    |> Enum.each(fn document ->
      {:ok, _signal} = Magma.signal(gate, document, %{})
      run_agency()
    end)
  end

  defp compliance_documents(:nsw) do
    [
      "document.contract",
      "document.title_search",
      "document.drainage_diagram",
      "document.planning_certificate"
    ]
  end

  defp compliance_documents(:vic) do
    ["document.vendor_statement", "document.statement_of_information", "document.title_search"]
  end

  defp compliance_documents(:qld) do
    ["document.form_6", "document.seller_disclosure", "document.title_search"]
  end

  defp proceed(workflow_id) do
    {:ok, _signal} =
      Magma.signal(campaign_of(workflow_id), "campaign.outcome", %{decision: :proceed})

    run_agency()
  end

  defp first_attempt_id(workflow_id) do
    Testing.recorded(campaign_of(workflow_id), :attempt).sale_attempt_id
  end

  defp open_first_attempt(workflow_id) do
    {:ok, _signal} =
      Magma.signal(campaign_of(workflow_id), "campaign.outcome", %{decision: :proceed})

    Testing.run_workflows(queue: :sales, with_recursion: false)
    first_attempt_id(workflow_id)
  end

  defp live_offer_ids(set_date_workflow_id) do
    Testing.recorded(set_date_workflow_id, :live_offers)
  end

  defp run_agency do
    Enum.each(1..3, fn _pass ->
      Testing.run_workflows(queue: :compliance)
      Testing.run_workflows(queue: :sales)
    end)
  end
end
