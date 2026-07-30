defmodule HelpdeskWeb.ConsoleTest do
  use HelpdeskWeb.ConnCase, async: true

  setup do
    northwind = an_organisation("Northwind")
    contoso = an_organisation("Contoso")

    ada = a_user(northwind, "Ada")
    a_user(northwind, "Grace", :manager)
    bea = a_user(contoso, "Bea")

    a_ticket(northwind, ada, "card declined")
    a_ticket(contoso, bea, "invoice is wrong")

    %{northwind: northwind, contoso: contoso, ada: ada}
  end

  defp open_console(conn) do
    {:ok, view, _html} = live(conn, ~p"/")

    view
  end

  defp switch_to(view, organisation) do
    view
    |> form("form[phx-change='organisation']", %{id: organisation.id})
    |> render_change()
  end

  defp raise_escalation(view) do
    view
    |> form("form[phx-submit='escalate']", %{reason: "customer waiting three days"})
    |> render_submit()

    run_escalations()

    {path, _flash} = assert_redirect(view)

    path
  end

  test "the queue shows only the organisation that is selected", %{conn: conn} = context do
    view = open_console(conn)

    assert queue(view) =~ "card declined"

    switch_to(view, context.contoso)

    assert queue(view) =~ "invoice is wrong"
    refute queue(view) =~ "card declined"
  end

  test "an agent can raise an escalation and land on its page", %{conn: conn} do
    view = open_console(conn)

    {:ok, page, html} = live(conn, raise_escalation(view))

    assert html =~ "escalation"
    assert render(page) =~ "waiting"
  end

  test "an agent holding nothing cannot get the ticket moved", %{conn: conn} = context do
    view = open_console(conn)
    path = raise_escalation(view)

    {:ok, page, _html} = live(conn, path)

    page
    |> form("form[phx-submit='approve']", %{assignee_id: context.ada.id})
    |> render_submit()

    run_escalations()

    assert repainted(page) =~ "failed"
    assert reload_ticket(context.northwind, hd(tickets(context)), context.ada).status == :open
  end

  test "granting the permission while the run waits lets the same approval through",
       %{conn: conn} = context do
    view = open_console(conn)
    path = raise_escalation(view)

    open_console(conn)
    |> element("button[phx-click='grant'][phx-value-id='#{context.ada.id}']")
    |> render_click()

    {:ok, page, _html} = live(conn, path)

    page
    |> form("form[phx-submit='approve']", %{assignee_id: context.ada.id})
    |> render_submit()

    run_escalations()

    assert repainted(page) =~ "completed"

    assert reload_ticket(context.northwind, hd(tickets(context)), context.ada).status ==
             :escalated
  end

  test "the run's page shows the identity it holds and the authority that identity has now",
       %{conn: conn} = context do
    view = open_console(conn)
    path = raise_escalation(view)

    {:ok, page, html} = live(conn, path)

    assert html =~ "Ada"
    assert html =~ "none"

    open_console(conn)
    |> element("button[phx-click='grant'][phx-value-id='#{context.ada.id}']")
    |> render_click()

    assert repainted(page) =~ "reassign_tickets"
  end

  defp queue(view), do: render(element(view, "form#escalate"))

  defp tickets(context) do
    {:ok, tickets} =
      Helpdesk.Support.list_tickets(tenant: context.northwind.id, actor: context.ada)

    tickets
  end
end
