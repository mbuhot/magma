defmodule HelpdeskWeb.EscalationLive do
  @moduledoc """
  One run, as the engine recorded it.

  The tape is this workflow's standing checkpoints, one row per completed step with the value
  it wrote. Above it are the two things magma persisted — an identity and a tenant — beside
  the permissions that identity resolves to at this moment. Those two panels are the point:
  the left one never changes, and the right one can change under a parked run.

  Approving is one call to `Magma.signal/3`. Whether the step it wakes is allowed is decided
  after the wait, not before it.
  """

  use HelpdeskWeb, :live_view

  alias Helpdesk.Accounts
  alias Helpdesk.Support.Escalation.Workflow

  @refresh 750

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, self(), :refresh)

    {:ok, socket |> assign(workflow_id: workflow_id, page_title: "escalation") |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("approve", %{"assignee_id" => assignee_id}, socket) do
    socket.assigns.workflow_id
    |> Workflow.decide(:approved, assignee_id)
    |> answered(socket, "Approved. The run wakes and reads its permissions afresh.")
  end

  def handle_event("reject", _params, socket) do
    socket.assigns.workflow_id
    |> Workflow.decide(:rejected, nil)
    |> answered(socket, "Rejected. Watch the undo put the ticket back.")
  end

  defp answered({:ok, _result}, socket, message),
    do: {:noreply, socket |> put_flash(:info, message) |> load()}

  defp answered({:error, error}, socket, _message),
    do: {:noreply, socket |> put_flash(:error, message(error)) |> load()}

  defp load(socket) do
    {:ok, workflow} = Magma.fetch(socket.assigns.workflow_id)

    socket
    |> assign(workflow: workflow, tape: tape(socket.assigns.workflow_id))
    |> assign(identity: identity(workflow), people: people(workflow))
  end

  defp tape(workflow_id), do: workflow_id |> Magma.steps() |> Enum.sort_by(& &1.id)

  # The row holds an id. This is what that id stands for right now, which is not what it stood
  # for when the run started if anything has been granted since.
  defp identity(%{actor: %{id: id}, tenant: tenant}) do
    case Accounts.get_user(id, tenant: tenant, load: [:permissions]) do
      {:ok, user} -> user
      _error -> nil
    end
  end

  defp identity(_workflow), do: nil

  defp people(%{tenant: tenant}) when is_binary(tenant) do
    {:ok, people} = Accounts.list_users(tenant: tenant)

    people
  end

  defp people(_workflow), do: []

  defp waiting?(%{status: :waiting}), do: true
  defp waiting?(_workflow), do: false

  defp message(error) when is_exception(error), do: Exception.message(error)
  defp message(error), do: inspect(error, pretty: true)

  defp value(term), do: inspect(term, pretty: true, limit: 8)

  @impl true
  def render(assigns) do
    ~H"""
    <h1>
      escalation <span class="mono">{String.slice(@workflow.id, 0, 8)}</span>
      <span class={"chip #{@workflow.status}"}>{@workflow.status}</span>
    </h1>

    <div class="grid" style="margin-bottom:1rem">
      <div class="panel">
        <h2>What the row holds</h2>
        <p class="hint">Written once, when the run started. Nothing here can go stale.</p>

        <table>
          <tr>
            <th>actor</th>
            <td class="mono value">{value(@workflow.actor)}</td>
          </tr>
          <tr>
            <th>tenant</th>
            <td class="mono value">{value(@workflow.tenant)}</td>
          </tr>
        </table>
      </div>

      <div class="panel">
        <h2>What that identity may do now</h2>
        <p class="hint">Read on every attempt, from the rows that stand at that moment.</p>

        <table :if={@identity}>
          <tr>
            <th>{@identity.name}</th>
            <td>{@identity.role}</td>
          </tr>
          <tr>
            <th>holds</th>
            <td class="mono">{Layouts.permissions(@identity.permissions)}</td>
          </tr>
        </table>
      </div>

      <div class="panel">
        <h2>Decide it</h2>
        <p :if={!waiting?(@workflow)} class="hint">
          This run is not parked on a decision.
        </p>

        <form :if={waiting?(@workflow)} id="decide" phx-submit="approve">
          <label>Move the ticket to</label>
          <select name="assignee_id">
            <option :for={person <- @people} value={person.id}>{person.name}</option>
          </select>

          <div class="row" style="margin-top:0.7rem">
            <button class="primary" type="submit">approve</button>
            <button class="danger" type="button" phx-click="reject">reject</button>
          </div>
        </form>
      </div>
    </div>

    <div class="panel">
      <h2>The tape</h2>
      <p class="hint">One row per step that finished, with the value it recorded.</p>

      <table>
        <tr>
          <th>Step</th>
          <th>Recorded</th>
        </tr>
        <tr :for={step <- @tape}>
          <td class="mono">{step.step_label}</td>
          <td class="mono value">{value(step.output)}</td>
        </tr>
      </table>

      <p :if={@tape == []} class="empty">Nothing has finished, or it has all been taken back.</p>
    </div>
    """
  end
end
