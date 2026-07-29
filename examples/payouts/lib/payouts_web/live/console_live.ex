defmodule PayoutsWeb.ConsoleLive do
  @moduledoc """
  Everything at once: who has money, what each rail wants of them, and every payout in flight.

  The page holds no state. It re-reads the store on a timer, because the work it starts is
  done by Oban somewhere else and finishes without telling this process.
  """

  use PayoutsWeb, :live_view

  alias Payouts.Offramp
  alias Payouts.Provider
  alias Payouts.Routing

  @refresh 750

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, self(), :refresh)

    {:ok, socket |> assign(page_title: "console", amount: "25000") |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("fund", %{"name" => name, "balance" => balance}, socket) do
    case Offramp.open_customer(name, String.to_integer(balance)) do
      {:ok, funded} ->
        {:noreply, socket |> put_flash(:info, "#{funded.name} has money.") |> load()}

      {:error, error} ->
        {:noreply, refused(socket, error)}
    end
  end

  @impl true
  def handle_event("onboard", %{"customer" => customer_id, "currency" => currency}, socket) do
    case Offramp.onboard(customer_id, currency) do
      {:ok, _onboarding} ->
        {:noreply, socket |> put_flash(:info, "Onboarding on the #{currency} rail.") |> load()}

      {:error, error} ->
        {:noreply, refused(socket, error)}
    end
  end

  @impl true
  def handle_event("register", %{"customer" => customer_id, "currency" => currency}, socket) do
    account = %{
      customer_id: customer_id,
      destination_currency: currency,
      account_number: "DE00BRDG" <> String.slice(customer_id, 0, 8),
      bank_code: "BRDGDEFF"
    }

    case Offramp.register_beneficiary(account) do
      {:ok, _beneficiary} ->
        {:noreply, socket |> put_flash(:info, "Registering the account.") |> load()}

      {:error, error} ->
        {:noreply, refused(socket, error)}
    end
  end

  @impl true
  def handle_event("request", %{"customer" => customer_id, "currency" => currency}, socket) do
    payout = %{
      customer_id: customer_id,
      destination_currency: currency,
      source_amount_cents: String.to_integer(socket.assigns.amount)
    }

    case Offramp.start_payout(payout) do
      {:ok, transfer} -> {:noreply, push_navigate(socket, to: ~p"/payouts/#{transfer.id}")}
      {:error, error} -> {:noreply, refused(socket, error)}
    end
  end

  @impl true
  def handle_event("amount", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, :amount, amount)}
  end

  @impl true
  def handle_event("arm", %{"call" => call}, socket) do
    Provider.fail_next(String.to_existing_atom(call))

    {:noreply, socket |> put_flash(:info, "The next #{call} will be refused.") |> load()}
  end

  defp refused(socket, error), do: socket |> put_flash(:error, Exception.message(error)) |> load()

  defp load(socket) do
    {:ok, customers} = Offramp.customer_standing()
    {:ok, transfers} = Offramp.transfer_feed()

    assign(socket,
      customers: customers,
      transfers: transfers,
      rails: Routing.rails(),
      armed: Provider.armed(),
      calls: Provider.tape()
    )
  end

  defp on_rail(records, currency), do: Enum.find(records, &(&1.destination_currency == currency))

  defp money(cents), do: PayoutsWeb.Layouts.money(cents)

  defp state_of(nil), do: "none"
  defp state_of(record), do: to_string(record.status)

  defp short(nil), do: "—"
  defp short(module), do: module |> Module.split() |> List.last()

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Customers</h1>

    <div class="panel" style="margin-bottom:1rem">
      <form id="fund" phx-submit="fund" class="row">
        <input type="text" name="name" placeholder="name" style="width:12rem" required />
        <input type="number" name="balance" value="100000" style="width:9rem" required />
        <button type="submit" class="primary">Fund a customer</button>
      </form>
    </div>

    <div class="panel" style="margin-bottom:1.6rem">
      <p :if={@customers == []} class="empty">No one yet.</p>

      <table :if={@customers != []}>
        <thead>
          <tr>
            <th>Customer</th>
            <th>Balance</th>
            <th>EUR rail</th>
            <th>USD rail</th>
            <th>Pay out</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={customer <- @customers}>
            <td>{customer.name}</td>
            <td class="mono">{money(customer.balance_cents)}</td>
            <td :for={currency <- ~w(EUR USD)}>
              <div class="row">
                <span class={["chip", state_of(on_rail(customer.onboardings, currency))]}>
                  kyc {state_of(on_rail(customer.onboardings, currency))}
                </span>
                <span class={["chip", state_of(on_rail(customer.beneficiaries, currency))]}>
                  account {state_of(on_rail(customer.beneficiaries, currency))}
                </span>
              </div>
              <div class="row" style="margin-top:0.4rem">
                <button phx-click="onboard" phx-value-customer={customer.id} phx-value-currency={currency}>
                  Onboard
                </button>
                <button phx-click="register" phx-value-customer={customer.id} phx-value-currency={currency}>
                  Register account
                </button>
              </div>
            </td>
            <td>
              <div class="row">
                <button
                  :for={currency <- ~w(EUR USD)}
                  class="primary"
                  phx-click="request"
                  phx-value-customer={customer.id}
                  phx-value-currency={currency}
                >
                  {currency}
                </button>
              </div>
              <form id={"amount-#{customer.id}"} phx-change="amount" style="margin-top:0.4rem">
                <input type="number" name="amount" value={@amount} style="width:8rem" />
              </form>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <h1>Payouts</h1>

    <div class="panel" style="margin-bottom:1.6rem">
      <p :if={@transfers == []} class="empty">Nothing has been asked for yet.</p>

      <table :if={@transfers != []}>
        <thead>
          <tr>
            <th>Customer</th>
            <th>Amount</th>
            <th>Transfer</th>
            <th>Workflow</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={transfer <- @transfers}>
            <td>{transfer.customer.name}</td>
            <td class="mono">
              {money(transfer.source_amount_cents)} → {transfer.destination_currency}
            </td>
            <td><span class={["chip", to_string(transfer.status)]}>{transfer.status}</span></td>
            <td>
              <span :if={transfer.workflow} class={["chip", to_string(transfer.workflow.status)]}>
                {transfer.workflow.status}
              </span>
              <span :if={is_nil(transfer.workflow)} class="empty">not started</span>
            </td>
            <td><.link navigate={~p"/payouts/#{transfer.id}"}>open →</.link></td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="grid">
      <div class="panel">
        <h2>Rails</h2>
        <table>
          <thead>
            <tr>
              <th>Currency</th>
              <th>Rail</th>
              <th>KYC</th>
              <th>Beneficiary</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={rail <- @rails}>
              <td class="mono">{rail.currency}</td>
              <td class="mono value">{short(rail.rail)}</td>
              <td class="mono value">{short(rail.onboarding)}</td>
              <td class="mono value">{short(rail.beneficiary)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="panel">
        <h2>Provider conditions</h2>
        <p class="hint">
          Arm a call to be refused once. The run fails, retries, and replays what it already did.
        </p>
        <div class="row">
          <button
            :for={call <- ~w(send_payout close_submission add_beneficiary)}
            class="danger"
            phx-click="arm"
            phx-value-call={call}
          >
            {call}
          </button>
        </div>
        <p :if={@armed != []} class="hint" style="margin-top:0.8rem">
          armed: <span class="mono">{@armed |> Enum.map_join(", ", &inspect/1)}</span>
        </p>
      </div>

      <div class="panel">
        <h2>Provider calls</h2>
        <p :if={@calls == []} class="empty">Nothing has been asked of the provider.</p>
        <ol :if={@calls != []} class="mono value" style="margin:0; padding-left:1.2rem">
          <li :for={call <- Enum.take(@calls, 20)}>{inspect(call)}</li>
        </ol>
      </div>
    </div>
    """
  end
end
