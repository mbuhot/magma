defmodule AgencyWeb.ConsoleLive do
  @moduledoc """
  The workflow inspector: every magma workflow the agency is running, how they dispatch one
  another, and one workflow's checkpoints, signals and waits.

  Where the sales desk translates a workflow's state into what an agent would say, this reads
  the other way — module names, step keys, signal names, queues — because the machinery
  itself is what a developer came here to see.
  """

  use AgencyWeb, :live_view

  alias AgencyWeb.ConsoleLive.Board

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, status_filter: :all)}

  @impl true
  def handle_params(params, _uri, socket) do
    workflows = Board.workflows()
    selected_id = params["id"] || workflow_id_of(List.first(workflows))

    {:noreply,
     socket
     |> assign(
       page_title: "Workflow console",
       workflows: workflows,
       tree: Board.tree(workflows),
       selected_id: selected_id
     )
     |> load_detail()}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/console/#{id}")}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, status_filter: parse_status(status))}
  end

  defp workflow_id_of(nil), do: nil
  defp workflow_id_of(workflow), do: workflow.id

  defp parse_status("all"), do: :all
  defp parse_status(status), do: String.to_existing_atom(status)

  defp load_detail(socket) do
    case socket.assigns.selected_id do
      nil -> assign(socket, detail: nil)
      id -> assign(socket, detail: Board.detail(id))
    end
  end

  defp filtered_workflows(assigns) do
    Board.filtered(assigns.status_filter, assigns.workflows)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="console">
      <h1>Workflow console</h1>
      <p style="color:var(--ink-2);font-size:13.5px;margin:4px 0 0">
        Every workflow this agency has started, how they dispatched one another, and what each one has done.
      </p>

      <div class="filters">
        <button class={@status_filter == :all && "on"} phx-click="filter" phx-value-status="all">
          all &middot; {length(@workflows)}
        </button>
        <button
          :for={status <- Board.statuses()}
          class={@status_filter == status && "on"}
          phx-click="filter"
          phx-value-status={status}
        >
          {status} &middot; {Enum.count(@workflows, &(&1.status == status))}
        </button>
      </div>

      <div class="console-grid">
        <div>
          <div class="card">
            <header><h3>Workflows</h3></header>
            <div class="tblwrap">
              <table class="tbl">
                <thead>
                  <tr>
                    <th>Module</th>
                    <th>Status</th>
                    <th>Queue</th>
                    <th>In status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={workflow <- filtered_workflows(assigns)}
                    class={["wf-row", workflow.id == @selected_id && "on"]}
                    phx-click="select"
                    phx-value-id={workflow.id}
                  >
                    <td>
                      <div class="mod">{Board.short(workflow.module)}</div>
                      <div class="mono-id">{workflow.id}</div>
                    </td>
                    <td><span class={["pill", status_class(workflow.status)]}>{workflow.status}</span></td>
                    <td class="mono">{Board.queue(workflow.module)}</td>
                    <td class="mono">{Board.in_status(workflow)}</td>
                  </tr>
                </tbody>
              </table>
              <p :if={filtered_workflows(assigns) == []} class="empty">No workflows in this status.</p>
            </div>
          </div>

          <div class="card">
            <header><h3>Dispatch tree</h3></header>
            <ul class="tree">
              <li :for={{workflow, children} <- @tree}>
                <.tree_node workflow={workflow} children={children} selected_id={@selected_id} />
              </li>
            </ul>
            <p :if={@tree == []} class="empty">No workflows have been started.</p>
          </div>
        </div>

        <div>
          {detail_panel(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp tree_node(assigns) do
    ~H"""
    <button
      class={["tree-row", @workflow.id == @selected_id && "on"]}
      phx-click="select"
      phx-value-id={@workflow.id}
    >
      <span class="mod">{Board.short(@workflow.module)}</span>
      <span class={["pill", status_class(@workflow.status)]}>{@workflow.status}</span>
      <span :if={@workflow.parent_signal} class="via">via {@workflow.parent_signal}</span>
    </button>
    <ul :if={@children != []}>
      <li :for={{child, grandchildren} <- @children}>
        <.tree_node workflow={child} children={grandchildren} selected_id={@selected_id} />
      </li>
    </ul>
    """
  end

  defp detail_panel(%{detail: nil} = assigns) do
    ~H"""
    <div class="card">
      <header><h3>Workflow</h3></header>
      <p class="empty">Select a workflow to inspect it.</p>
    </div>
    """
  end

  defp detail_panel(assigns) do
    ~H"""
    <div class="card">
      <header>
        <div class="detail-head">
          <div>
            <h2>{Board.short(@detail.workflow.module)}</h2>
            <div class="mono-id">{@detail.workflow.id}</div>
            <div :if={@detail.parent} class="parent">
              Dispatched by {Board.short(@detail.parent.module)}, reporting on "{@detail.workflow.parent_signal}"
              <button phx-click="select" phx-value-id={@detail.parent.id}>open →</button>
            </div>
          </div>
          <div>
            <span class={["pill", status_class(@detail.workflow.status)]}>{@detail.workflow.status}</span>
            <div class="mono-id" style="text-align:right;margin-top:4px">
              {Board.queue(@detail.workflow.module)} queue &middot; {Board.in_status(@detail.workflow)}
            </div>
          </div>
        </div>
      </header>

      <div class="pad">
        <h3 style="margin:0 0 8px;font-size:14px">Parked on</h3>
        <div :if={@detail.waiters == []} class="parked">Not parked on anything right now.</div>
        <div :for={waiter <- @detail.waiters} class="parked">
          <span class="sig">{waiter.name}</span>
          <span class="pill">{waiter.kind}</span>
          <span :if={waiter.deadline} class="dl">{Board.deadline_words(waiter.deadline)}</span>
        </div>
      </div>

      <header><h3>Checkpoints</h3></header>
      <ol class="steps">
        <li :for={checkpoint <- @detail.checkpoints}>
          <div class="lab">{checkpoint.step_label}</div>
          <details>
            <summary>{Board.preview(checkpoint.output)}</summary>
            <pre>{Board.full(checkpoint.output)}</pre>
          </details>
        </li>
      </ol>
      <p :if={@detail.checkpoints == []} class="empty">Nothing has completed yet.</p>
      <p class="note">
        A switch only checkpoints the arm it took — the others never ran, so their steps never appear here.
      </p>

      <header><h3>Signals</h3></header>
      <ol class="steps">
        <li :for={signal <- @detail.signals}>
          <div class="lab">
            {signal.name}
            <span class={["pill", signal.consumed_at && "ok"]}>
              {if signal.consumed_at, do: "consumed", else: "pending"}
            </span>
          </div>
          <details>
            <summary>{Board.preview(signal.payload)}</summary>
            <pre>{Board.full(signal.payload)}</pre>
          </details>
        </li>
      </ol>
      <p :if={@detail.signals == []} class="empty">No signal has reached this workflow.</p>
    </div>
    """
  end

  defp status_class(status) when status in [:completed], do: "ok"
  defp status_class(status) when status in [:failed, :cancelled], do: "bad"

  defp status_class(status) when status in [:waiting, :polling, :cancelling, :unwinding],
    do: "act"

  defp status_class(_pending), do: ""
end
