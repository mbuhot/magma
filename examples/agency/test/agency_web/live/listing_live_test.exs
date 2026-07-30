defmodule AgencyWeb.ListingLiveTest do
  use AgencyWeb.ConnCase, async: true

  alias Agency.Sale

  defp seed do
    Agency.Seeds.seed!()
  end

  defp the_sale_workflow(agreement) do
    agreement.id
    |> AgencyWeb.ListingLive.Workflows.engagement_id()
    |> Magma.child_id(:campaign)
    |> Magma.child_id(:sale_attempt)
  end

  defp listing_named(address) do
    Sale.list_agreements!(load: [:property]) |> Enum.find(&(&1.property.address == address))
  end

  defp a_fresh_set_date_listing do
    property =
      Sale.add_property!(%{address: "9 Bellevue Street", suburb: "Testville", jurisdiction: :nsw})

    agreement =
      Sale.sign_agreement!(%{
        property_id: property.id,
        vendor_name: "A. Vendor",
        agent_name: "Priya Chandra",
        appointment: :exclusive,
        term_start: Date.utc_today(),
        term_end: Date.add(Date.utc_today(), 90),
        commission_rate: Decimal.new("2.2"),
        commission_trigger: :on_settlement,
        sale_method: :set_date,
        guide_price: 1_000_000_00
      })

    danforth = Sale.register_buyer!(%{agency_agreement_id: agreement.id, name: "Danforth"})
    osei_bright = Sale.register_buyer!(%{agency_agreement_id: agreement.id, name: "Osei-Bright"})

    {:ok, workflow} =
      Magma.start(Agency.Sale.Engagement, %{agency_agreement_id: agreement.id}, queue: :sales)

    run_agency()

    gate = Magma.child_id(workflow.id, :compliance_gate)

    ~w(document.contract document.title_search document.drainage_diagram document.planning_certificate)
    |> Enum.each(fn document ->
      {:ok, _signal} = Magma.signal(gate, document, %{})
      run_agency()
    end)

    campaign = Magma.child_id(workflow.id, :campaign)

    {:ok, _signal} = Magma.signal(campaign, "campaign.outcome", %{decision: :proceed})
    run_agency()

    attempt_id = Magma.Testing.recorded(campaign, :attempt).sale_attempt_id

    Sale.make_offer!(%{
      sale_attempt_id: attempt_id,
      buyer_id: danforth.id,
      amount: 1_010_000_00,
      requested_conditions: [:finance],
      expires_at: Agency.Sale.Window.offer_expiry()
    })

    Sale.make_offer!(%{
      sale_attempt_id: attempt_id,
      buyer_id: osei_bright.id,
      amount: 1_020_000_00,
      requested_conditions: [:finance],
      expires_at: Agency.Sale.Window.offer_expiry()
    })

    agreement
  end

  test "an empty database points a newcomer at the seed task", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "No listings yet"
    assert html =~ "mix agency.seed"
  end

  test "each seeded listing shows a distinct state of its own", %{conn: conn} do
    seed()

    {:ok, _view, kurraba_html} = live(conn, ~p"/listings/#{listing_named("14 Kurraba Road").id}")
    assert kurraba_html =~ "Offers are open"
    assert kurraba_html =~ "Danforth"

    {:ok, _view, rialto_html} = live(conn, ~p"/listings/#{listing_named("8 Rialto Street").id}")
    assert rialto_html =~ "Auction day"
    assert rialto_html =~ "Nakagawa"

    {:ok, _view, ardoyne_html} = live(conn, ~p"/listings/#{listing_named("22 Ardoyne Road").id}")
    assert ardoyne_html =~ "Cooling off"
    assert ardoyne_html =~ "Whitlam"

    {:ok, _view, marine_html} = live(conn, ~p"/listings/#{listing_named("51 Marine Parade").id}")
    assert marine_html =~ "fell through"
    assert marine_html =~ "Rasmussen"
    assert marine_html =~ "Re-approach the underbidders"
  end

  test "calling back a named underbidder puts that buyer back in negotiation", %{conn: conn} do
    seed()
    marine = listing_named("51 Marine Parade")

    {:ok, view, html} = live(conn, ~p"/listings/#{marine.id}")

    assert html =~ "Re-approach Pettifer at $2,445,000"
    assert html =~ "Re-approach Choudhury at $2,412,000"
    assert html =~ "Cash purchase"
    assert html =~ "Finance through Meridian Bank"

    html =
      view
      |> element("button[phx-click='re_approach']", "Choudhury")
      |> render_click()

    assert html =~ "Negotiating"
    refute html =~ "Re-approach the underbidders"
  end

  test "relaunching the campaign puts the listing back on the market", %{conn: conn} do
    seed()
    marine = listing_named("51 Marine Parade")

    {:ok, view, _html} = live(conn, ~p"/listings/#{marine.id}")

    html = view |> element("button[phx-click='relaunch_campaign']") |> render_click()

    assert html =~ "Ready to go to market"
    assert html =~ "Launch the campaign"
  end

  test "clicking a listing in the picker shows that listing instead", %{conn: conn} do
    seed()
    kurraba = listing_named("14 Kurraba Road")
    rialto = listing_named("8 Rialto Street")

    {:ok, view, html} = live(conn, ~p"/listings/#{kurraba.id}")
    assert html =~ "Danforth"
    refute html =~ "Nakagawa"

    html = view |> element("button[phx-value-id='#{rialto.id}']") |> render_click()

    assert html =~ "Nakagawa"
    refute html =~ "Danforth"
  end

  test "closing offers and answering a buyer changes that buyer's position", %{conn: conn} do
    agreement = a_fresh_set_date_listing()

    {:ok, view, html} = live(conn, ~p"/listings/#{agreement.id}")
    assert html =~ "Offer on the table"
    refute html =~ "Accepted, awaiting the vendor"

    view |> element("button[phx-click='close_offers']") |> render_click()

    html =
      view
      |> element("button[phx-click='accept_offer']", "Osei-Bright")
      |> render_click()

    assert html =~ "Accepted, awaiting the vendor"
  end

  test "a rescission opens the register back up and shows the forfeit and written-back commission",
       %{conn: conn} do
    seed()
    ardoyne = listing_named("22 Ardoyne Road")

    {:ok, view, html} = live(conn, ~p"/listings/#{ardoyne.id}")
    assert html =~ "Whitlam rescinds during cooling off"

    html = view |> element("button[phx-click='rescind']") |> render_click()

    assert html =~ "fell through"
    assert html =~ "forfeited"
    assert html =~ "Written back"
  end

  test "resolving every condition moves the listing to awaiting settlement", %{conn: conn} do
    seed()
    ardoyne = listing_named("22 Ardoyne Road")
    let_the_wait_lapse(the_sale_workflow(ardoyne), "cooling_off.rescission")

    {:ok, view, html} = live(conn, ~p"/listings/#{ardoyne.id}")
    assert html =~ "Conditions to satisfy"

    view |> element("button[phx-click='finance_approved']") |> render_click()
    view |> element("button[phx-click='inspection_satisfied']") |> render_click()
    html = view |> element("button[phx-click='title_clear']") |> render_click()

    assert html =~ "Settlement due"
  end

  test "settling a contract shows the commission as paid", %{conn: conn} do
    seed()
    rialto = listing_named("8 Rialto Street")

    {:ok, view, _html} = live(conn, ~p"/listings/#{rialto.id}")
    view |> element("button[phx-click='sold_under_the_hammer']") |> render_click()

    html = repainted(view)
    assert html =~ "Conditions to satisfy"

    view |> element("button[phx-click='finance_approved']") |> render_click()
    view |> element("button[phx-click='inspection_satisfied']") |> render_click()
    html = view |> element("button[phx-click='title_clear']") |> render_click()
    assert html =~ "Settlement due"

    html = view |> element("button[phx-click='settle']") |> render_click()

    assert html =~ "Settled"
    assert html =~ "Paid "
  end
end
