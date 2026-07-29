defmodule PayoutsWeb.ConsoleTest do
  use PayoutsWeb.ConnCase, async: true

  alias Payouts.Offramp

  defp open_console(conn) do
    {:ok, view, _html} = live(conn, ~p"/")
    view
  end

  defp request_payout(view, customer, currency) do
    view
    |> element(
      "button[phx-value-customer='#{customer.id}'][phx-value-currency='#{currency}'][phx-click='request']"
    )
    |> render_click()

    settle_queues()

    assert_redirect(view)
  end

  defp open_payout(conn, path) do
    {:ok, view, _html} = live(conn, path)
    view
  end

  defp click(view, selector) do
    render_click(element(view, selector))
    settle_queues()

    repainted(view)
  end

  defp balance(customer) do
    {:ok, reloaded} = Offramp.get_customer(customer.id)
    reloaded.balance_cents
  end

  test "funding a customer puts them on the console", %{conn: conn} do
    view = open_console(conn)

    html =
      view
      |> form("form[phx-submit='fund']", %{name: "Grace", balance: "100000"})
      |> render_submit()

    assert html =~ "Grace"
    assert html =~ "1000.00"
  end

  test "a customer the rail has never been told about cannot be paid", %{conn: conn} do
    customer = a_customer(100_000)

    view = open_console(conn)
    {path, _flash} = request_payout(view, customer, "EUR")

    html = conn |> open_payout(path) |> render()

    assert html =~ "failed"
    assert html =~ "Why it stopped"
    assert html =~ "has not been onboarded on the EUR rail"
    assert balance(customer) == 100_000
  end

  test "a customer with no account registered says so on the payout", %{conn: conn} do
    customer = a_customer(100_000)
    an_onboarding(customer)

    view = open_console(conn)
    {path, _flash} = request_payout(view, customer, "EUR")

    html = conn |> open_payout(path) |> render()

    assert html =~ "no registered EUR beneficiary"
    assert balance(customer) == 100_000
  end

  test "the payout waits for the customer to approve the quote", %{conn: conn} do
    customer = a_customer(100_000)
    ready_for_rail(customer)

    view = open_console(conn)
    {path, _flash} = request_payout(view, customer, "EUR")

    html = conn |> open_payout(path) |> render()

    assert html =~ "the customer to approve the quote"
    assert html =~ "The customer has not been debited"
    assert balance(customer) == 100_000
  end

  test "approving the quote debits the customer and hands the transfer to the rail", %{conn: conn} do
    customer = a_customer(100_000)
    ready_for_rail(customer)

    view = open_console(conn)
    {path, _flash} = request_payout(view, customer, "EUR")

    html = conn |> open_payout(path) |> click("button[phx-click='approve']")

    assert html =~ "the rail&#39;s webhook to say how it went"
    assert html =~ "Payouts.Rails.Bridge"
    assert balance(customer) == 75_000
  end

  test "the webhook saying it settled completes the payout", %{conn: conn} do
    customer = a_customer(100_000)
    ready_for_rail(customer)

    view = open_console(conn)
    {path, _flash} = request_payout(view, customer, "EUR")

    payout = open_payout(conn, path)
    click(payout, "button[phx-click='approve']")

    html = click(payout, "button[phx-value-outcome='completed']")

    assert html =~ "completed"
    assert balance(customer) == 75_000
  end

  test "the webhook saying it was rejected gives the customer their money back", %{conn: conn} do
    customer = a_customer(100_000)
    ready_for_rail(customer)

    view = open_console(conn)
    {path, _flash} = request_payout(view, customer, "EUR")

    payout = open_payout(conn, path)
    click(payout, "button[phx-click='approve']")

    html = click(payout, "button[phx-value-outcome='rejected']")

    assert html =~ "payout reversal"
    assert html =~ "the provider rejected transfer"
    assert balance(customer) == 100_000
  end
end
