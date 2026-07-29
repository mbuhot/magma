defmodule PayoutsWeb.PayoutLive do
  @moduledoc """
  One payout, as the engine recorded it.

  The tape down the page is this workflow's standing checkpoints: one row per completed step,
  in the order they finished, carrying the value that was written. The rail's own tape sits
  under it, since the rail is a separate workflow with a separate row of checkpoints.

  The two controls on the right are the two moments a payout waits on somebody. Approving the
  quote is the customer answering; settling is the rail's webhook arriving. Both are the same
  thing to magma — a signal against a name the workflow parked on.
  """

  use PayoutsWeb, :live_view

  alias Payouts.Offramp

  @refresh 750

  @impl true
  def mount(%{"id" => transfer_id}, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, self(), :refresh)

    {:ok, socket |> assign(transfer_id: transfer_id, page_title: "payout") |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("approve", _params, socket) do
    socket.assigns.transfer_id
    |> Offramp.approve_quote()
    |> answered(socket, "Quote approved. The rail has it now.")
  end

  @impl true
  def handle_event("settle", %{"outcome" => outcome}, socket) do
    socket.assigns.transfer_id
    |> Offramp.deliver_settlement(String.to_existing_atom(outcome))
    |> answered(socket, "Webhook delivered: #{outcome}.")
  end

  @impl true
  def handle_event("resume", _params, socket) do
    socket.assigns.transfer_id
    |> Offramp.resume_payout()
    |> answered(socket, "Queued a run. It replays from its last checkpoint.")
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    socket.assigns.transfer_id
    |> Offramp.cancel_payout()
    |> answered(socket, "Cancelling. Watch the undos take it back.")
  end

  defp answered({:ok, _result}, socket, message), do: {:noreply, said(socket, message)}
  defp answered({:error, error}, socket, _message), do: {:noreply, refused(socket, error)}

  defp said(socket, message), do: socket |> put_flash(:info, message) |> load()

  defp refused(socket, error) when is_exception(error),
    do: socket |> put_flash(:error, Exception.message(error)) |> load()

  defp refused(socket, error), do: socket |> put_flash(:error, inspect(error)) |> load()

  defp load(socket) do
    {:ok, transfer} = Offramp.payout(socket.assigns.transfer_id)

    assign(socket, :transfer, transfer)
  end

  defp waiting_on?(waiters, name), do: Enum.any?(waiters, &(&1.name == name))

  defp money(cents), do: PayoutsWeb.Layouts.money(cents)

  defp reason(error) when is_exception(error), do: Exception.message(error)
  defp reason(error), do: inspect(error, pretty: true)

  defp asking(%{name: "confirm"}), do: "the customer to approve the quote"
  defp asking(%{name: "settlement"}), do: "the rail's webhook to say how it went"
  defp asking(%{name: name}), do: name

  @impl true
  def render(assigns) do
    ~H"""
    <h1>
      {@transfer.customer.name} — {money(@transfer.source_amount_cents)} → {@transfer.destination_currency}
      <span class={["chip", to_string(@transfer.status)]}>{@transfer.status}</span>
      <span :if={@transfer.workflow} class={["chip", to_string(@transfer.workflow.status)]}>{@transfer.workflow.status}</span>
    </h1>

    <div class="grid">
      <div>
        <div class="panel" style="margin-bottom:1rem">
          <h2>Checkpoints</h2>
          <p :if={@transfer.tape == []} class="empty">Nothing recorded yet.</p>

          <table :if={@transfer.tape != []}>
            <tbody>
              <tr :for={step <- @transfer.tape}>
                <td class="mono" style="width:11rem">{step.step_label}</td>
                <td class="mono value">{inspect(step.output, pretty: true, limit: 6)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="panel" style="margin-bottom:1rem">
          <h2>The rail's own workflow</h2>
          <p class="hint">
            <span :if={@transfer.rail}>{inspect(@transfer.rail.module)}</span>
            <span :if={is_nil(@transfer.rail)} class="empty">The rail has not been dispatched yet.</span>
          </p>

          <table :if={@transfer.rail_tape != []}>
            <tbody>
              <tr :for={step <- @transfer.rail_tape}>
                <td class="mono" style="width:11rem">{step.step_label}</td>
                <td class="mono value">{inspect(step.output, pretty: true, limit: 6)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="panel">
          <h2>Ledger</h2>
          <p :if={@transfer.ledger_entries == []} class="empty">The customer has not been debited.</p>

          <table :if={@transfer.ledger_entries != []}>
            <tbody>
              <tr :for={entry <- @transfer.ledger_entries}>
                <td>{entry.reason}</td>
                <td class="mono">{money(entry.amount_cents)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div>
        <div :if={@transfer.workflow && @transfer.workflow.error} class="panel" style="margin-bottom:1rem">
          <h2>Why it stopped</h2>
          <p class="mono value">{reason(@transfer.workflow.error)}</p>
        </div>

        <div class="panel" style="margin-bottom:1rem">
          <h2>Waiting on</h2>
          <p :if={@transfer.waiting_on == []} class="empty">Not parked — it is running or finished.</p>

          <table :if={@transfer.waiting_on != []}>
            <tbody>
              <tr :for={waiter <- @transfer.waiting_on}>
                <td>{asking(waiter)}</td>
                <td class="mono value">{waiter.deadline && "until #{waiter.deadline}"}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="panel" style="margin-bottom:1rem">
          <h2>The customer</h2>
          <p class="hint">
            The quote is shown, and nothing is debited, until this is answered. The amount that
            leaves the balance is the amount on the quote checkpoint, whatever the price has done
            since.
          </p>
          <button class="primary" phx-click="approve" disabled={not waiting_on?(@transfer.waiting_on, "confirm")}>
            Approve the quote
          </button>
        </div>

        <div class="panel" style="margin-bottom:1rem">
          <h2>The rail's webhook</h2>
          <p class="hint">
            The money has left and the rail has been told to send it. This is the callback saying
            whether it landed. A rejection unwinds the run and gives the money back.
          </p>
          <div class="row">
            <button
              class="primary"
              phx-click="settle"
              phx-value-outcome="completed"
              disabled={not waiting_on?(@transfer.waiting_on, "settlement")}
            >
              Settled
            </button>
            <button
              class="danger"
              phx-click="settle"
              phx-value-outcome="rejected"
              disabled={not waiting_on?(@transfer.waiting_on, "settlement")}
            >
              Rejected
            </button>
          </div>
        </div>

        <div class="panel">
          <h2>Interfere</h2>
          <p class="hint">
            Resuming is what recovery does after a crash: the run comes back and replays every
            checkpoint above rather than doing any of it again.
          </p>
          <div class="row">
            <button phx-click="resume">Resume</button>
            <button class="danger" phx-click="cancel">Cancel</button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
