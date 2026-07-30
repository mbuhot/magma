defmodule HelpdeskWeb.TicketTest do
  use HelpdeskWeb.ConnCase, async: true

  setup do
    northwind = an_organisation("Northwind Traders")

    ada = a_user(northwind, "Ada Lovelace")
    ben = a_user(northwind, "Ben Okri")
    grace = a_user(northwind, "Grace Hopper", :team_lead)
    ticket = a_ticket(northwind, ada, "Card declined at checkout")

    %{northwind: northwind, ada: ada, ben: ben, grace: grace, ticket: ticket}
  end

  defp open_ticket(conn, context, person) do
    {:ok, view, html} =
      live(conn, ~p"/tickets/#{context.ticket.id}?#{[org: context.northwind.id, as: person.id]}")

    {view, html}
  end

  defp request_escalation(view) do
    view
    |> form("#escalate", %{reason: "The customer has been waiting three days."})
    |> render_submit()

    run_escalations()

    repainted(view)
  end

  defp decide(view, event, params \\ %{}) do
    case event do
      :approve -> view |> form("#decide", params) |> render_submit()
      :decline -> view |> element("button[phx-click='decline']") |> render_click()
    end

    run_escalations()

    repainted(view)
  end

  test "an agent can ask for an escalation", %{conn: conn} = context do
    {view, _html} = open_ticket(conn, context, context.ada)

    html = request_escalation(view)

    assert html =~ "Escalation requested"
    assert html =~ "Waiting on a team lead"
  end

  test "an agent is not offered the decision", %{conn: conn} = context do
    {view, _html} = open_ticket(conn, context, context.ada)

    html = request_escalation(view)

    refute html =~ "An escalation is waiting on you"
  end

  test "a team lead is offered the decision on somebody else's request",
       %{conn: conn} = context do
    {agents_view, _html} = open_ticket(conn, context, context.ada)
    request_escalation(agents_view)

    {_view, html} = open_ticket(conn, context, context.grace)

    assert html =~ "An escalation is waiting on you"
  end

  test "approving moves the ticket to whoever the team lead picked",
       %{conn: conn} = context do
    {agents_view, _html} = open_ticket(conn, context, context.ada)
    request_escalation(agents_view)

    {leads_view, _html} = open_ticket(conn, context, context.grace)
    html = decide(leads_view, :approve, %{assignee_id: context.ben.id})

    assert html =~ "escalated"
    assert html =~ "Held by Ben Okri"
  end

  test "declining leaves the ticket with whoever had it", %{conn: conn} = context do
    {agents_view, _html} = open_ticket(conn, context, context.ada)
    request_escalation(agents_view)

    {leads_view, _html} = open_ticket(conn, context, context.grace)
    html = decide(leads_view, :decline)

    assert html =~ "Held by Ada Lovelace"
    assert html =~ "the ticket is unchanged"
  end

  test "an agent given cover while their request waits can then decide it themselves",
       %{conn: conn} = context do
    {view, _html} = open_ticket(conn, context, context.ada)
    request_escalation(view)

    {:ok, queue, _html} =
      live(conn, ~p"/?#{[org: context.northwind.id, as: context.grace.id]}")

    queue
    |> element("button[phx-click='cover'][phx-value-id='#{context.ada.id}']")
    |> render_click()

    assert repainted(view) =~ "An escalation is waiting on you"

    html = decide(view, :approve, %{assignee_id: context.ben.id})

    assert html =~ "Held by Ben Okri"
  end

  defp resolve(view) do
    view |> element("button[phx-click='resolve']") |> render_click()

    run_escalations()

    repainted(view)
  end

  test "anybody can resolve a ticket they are looking at", %{conn: conn} = context do
    {view, _html} = open_ticket(conn, context, context.ben)

    html = resolve(view)

    assert html =~ "closed"
    assert html =~ "Nothing further happens to this ticket"
  end

  test "a resolved ticket cannot be escalated by anybody", %{conn: conn} = context do
    {view, _html} = open_ticket(conn, context, context.ada)

    html = resolve(view)

    refute html =~ "Ask for an escalation"

    {_leads_view, leads_html} = open_ticket(conn, context, context.grace)

    refute leads_html =~ "Ask for an escalation"
  end

  test "resolving a ticket takes back an escalation still waiting on it",
       %{conn: conn} = context do
    {view, _html} = open_ticket(conn, context, context.ada)
    request_escalation(view)

    html = resolve(view)

    refute html =~ "Waiting on a team lead"
    assert html =~ "Escalation taken back when the ticket was resolved"

    {_leads_view, leads_html} = open_ticket(conn, context, context.grace)

    refute leads_html =~ "An escalation is waiting on you"
  end

  test "a ticket already open shows the decision somebody else just made",
       %{conn: conn} = context do
    {agents_view, _html} = open_ticket(conn, context, context.ada)
    request_escalation(agents_view)

    {leads_view, _html} = open_ticket(conn, context, context.grace)
    decide(leads_view, :approve, %{assignee_id: context.ben.id})

    assert repainted(agents_view) =~ "Held by Ben Okri"
  end

  test "the history says what happened, in the order it happened", %{conn: conn} = context do
    {agents_view, _html} = open_ticket(conn, context, context.ada)
    request_escalation(agents_view)

    {leads_view, _html} = open_ticket(conn, context, context.grace)
    html = decide(leads_view, :approve, %{assignee_id: context.ben.id})

    assert html =~ "Ticket opened"
    assert html =~ "Escalation approved, and the ticket was reassigned"
    assert html =~ "Grace Hopper decided an escalation"
  end
end
