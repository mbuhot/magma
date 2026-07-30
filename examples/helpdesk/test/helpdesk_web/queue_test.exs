defmodule HelpdeskWeb.QueueTest do
  use HelpdeskWeb.ConnCase, async: true

  setup do
    northwind = an_organisation("Northwind Traders")
    contoso = an_organisation("Contoso Freight")

    ada = a_user(northwind, "Ada Lovelace")
    ben = a_user(northwind, "Ben Okri")
    grace = a_user(northwind, "Grace Hopper", :team_lead)
    bea = a_user(contoso, "Bea Nkemelu")

    a_ticket(northwind, ada, "Card declined at checkout")
    bens_ticket = a_ticket(northwind, ben, "Cannot reset my password")
    a_ticket(contoso, bea, "Invoice is for the wrong month")

    %{
      northwind: northwind,
      contoso: contoso,
      ada: ada,
      ben: ben,
      grace: grace,
      bea: bea,
      bens_ticket: bens_ticket
    }
  end

  defp open_queue(conn, organisation, person) do
    {:ok, view, html} = live(conn, ~p"/?#{[org: organisation.id, as: person.id]}")

    {view, html}
  end

  defp switch_person(view, person) do
    view |> form("#actor", %{actor_id: person.id}) |> render_change()
  end

  test "somebody sees the tickets they are holding", %{conn: conn} = context do
    {_view, html} = open_queue(conn, context.northwind, context.ada)

    assert html =~ "Card declined at checkout"
    refute html =~ "Cannot reset my password"
  end

  test "switching person shows that person's queue instead", %{conn: conn} = context do
    {view, _html} = open_queue(conn, context.northwind, context.ada)

    html = switch_person(view, context.ben)

    assert html =~ "Cannot reset my password"
    refute html =~ "Card declined at checkout"
  end

  test "switching organisation offers that organisation's people", %{conn: conn} = context do
    {view, html} = open_queue(conn, context.northwind, context.ada)

    assert html =~ "Ada Lovelace"

    html =
      view |> form("#organisation", %{organisation_id: context.contoso.id}) |> render_change()

    assert html =~ "Bea Nkemelu"
    refute html =~ "Ada Lovelace"
  end

  test "the team tab shows everything open, not only your own", %{conn: conn} = context do
    {view, _html} = open_queue(conn, context.northwind, context.ada)

    html = view |> element("a", "Open across the team") |> render_click()

    assert html =~ "Card declined at checkout"
    assert html =~ "Cannot reset my password"
  end

  test "a resolved ticket leaves the team's open list", %{conn: conn} = context do
    {:ok, bens_page, _html} =
      live(
        conn,
        ~p"/tickets/#{context.bens_ticket.id}?#{[org: context.northwind.id, as: context.ben.id]}"
      )

    bens_page |> element("button[phx-click='resolve']") |> render_click()

    {view, _html} = open_queue(conn, context.northwind, context.ada)
    html = view |> element("a", "Open across the team") |> render_click()

    assert html =~ "Card declined at checkout"
    refute html =~ "Cannot reset my password"
  end

  test "a queue already open catches up with what happened elsewhere",
       %{conn: conn} = context do
    {view, _html} = open_queue(conn, context.northwind, context.ada)
    html = view |> element("a", "Open across the team") |> render_click()

    assert html =~ "Cannot reset my password"

    {:ok, bens_page, _html} =
      live(
        conn,
        ~p"/tickets/#{context.bens_ticket.id}?#{[org: context.northwind.id, as: context.ben.id]}"
      )

    bens_page |> element("button[phx-click='resolve']") |> render_click()

    refute repainted(view) =~ "Cannot reset my password"
  end

  test "an agent is not shown who can act on escalations", %{conn: conn} = context do
    {_view, html} = open_queue(conn, context.northwind, context.ada)

    refute html =~ "Who can act on escalations"
  end

  test "a team lead can give an agent cover, and take it back", %{conn: conn} = context do
    {view, html} = open_queue(conn, context.northwind, context.grace)

    assert html =~ "Who can act on escalations"

    html =
      view
      |> element("button[phx-click='cover'][phx-value-id='#{context.ada.id}']")
      |> render_click()

    assert html =~ "They can act on escalations now"

    html =
      view
      |> element("button[phx-click='uncover'][phx-value-id='#{context.ada.id}']")
      |> render_click()

    assert html =~ "Cover withdrawn"
  end
end
