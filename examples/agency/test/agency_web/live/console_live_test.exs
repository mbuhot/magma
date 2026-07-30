defmodule AgencyWeb.ConsoleLiveTest do
  use AgencyWeb.ConnCase, async: true

  alias Agency.Sale.Engagement

  defp engaged_listing do
    agreement = a_signed_listing()

    {:ok, workflow} =
      Magma.start(Engagement, %{agency_agreement_id: agreement.id}, queue: :sales)

    run_agency()

    gate = Magma.child_id(workflow.id, :compliance_gate)

    ~w(document.vendor_statement document.statement_of_information document.title_search)
    |> Enum.each(fn document ->
      {:ok, _signal} = Magma.signal(gate, document, %{})
      run_agency()
    end)

    workflow
  end

  test "the sales desk links through to the workflow console and back", %{conn: conn} do
    a_signed_listing()

    {:ok, view, _html} = live(conn, ~p"/")

    {:error, {:live_redirect, %{to: console_path}}} =
      view |> element("a", "Workflow console") |> render_click()

    {:ok, console_view, console_html} = live(conn, console_path)
    assert console_html =~ "Workflow console"

    {:error, {:live_redirect, %{to: desk_path}}} =
      console_view |> element("a", "Sales desk") |> render_click()

    {:ok, _desk_view, desk_html} = live(conn, desk_path)
    assert desk_html =~ "Ray"
  end

  test "the console lists every workflow with its status", %{conn: conn} do
    engaged_listing()

    {:ok, _view, html} = live(conn, ~p"/console")

    assert html =~ "Engagement"
    assert html =~ "Campaign"
    assert html =~ "Gate"
    assert html =~ "waiting"
    assert html =~ "completed"
  end

  test "selecting a workflow shows the steps it has completed", %{conn: conn} do
    workflow = engaged_listing()
    gate_id = Magma.child_id(workflow.id, :compliance_gate)

    {:ok, view, _html} = live(conn, ~p"/console")

    html = view |> element("button[phx-value-id='#{gate_id}']", "Gate") |> render_click()

    assert html =~ ":vendor_statement_document"
    assert html =~ ":title_search_document"
  end

  test "the tree shows the campaign dispatched beneath its engagement", %{conn: conn} do
    workflow = engaged_listing()
    campaign_id = Magma.child_id(workflow.id, :campaign)

    {:ok, view, _html} = live(conn, ~p"/console")

    html = view |> element("button[phx-value-id='#{campaign_id}']", "Campaign") |> render_click()

    assert html =~ "Dispatched by Engagement"
  end

  test "a parked workflow shows the signal it is waiting on", %{conn: conn} do
    workflow = engaged_listing()
    campaign_id = Magma.child_id(workflow.id, :campaign)

    {:ok, view, _html} = live(conn, ~p"/console")

    html = view |> element("button[phx-value-id='#{campaign_id}']", "Campaign") |> render_click()

    assert html =~ "campaign.outcome"
    assert html =~ "Parked on"
  end

  test "filtering by status changes which workflows are listed", %{conn: conn} do
    engaged_listing()

    {:ok, view, _html} = live(conn, ~p"/console")

    all_rows = view |> element(".tbl") |> render()
    assert all_rows =~ "Engagement"
    assert all_rows =~ "Campaign"
    assert all_rows =~ "Gate"

    view |> element("button[phx-value-status='completed']") |> render_click()
    completed_rows = view |> element(".tbl") |> render()

    assert completed_rows =~ "Gate"
    refute completed_rows =~ "Engagement"
    refute completed_rows =~ "Campaign"
  end
end
