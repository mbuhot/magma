defmodule HelpdeskWeb.Layouts do
  @moduledoc """
  The application's chrome: the document, the top bar, and the whole stylesheet.

  The style lives here as a string rather than in an asset pipeline, so the example runs with
  nothing built.
  """

  use HelpdeskWeb, :html

  import HelpdeskWeb.Viewer, only: [switcher: 1]

  @stylesheet """
  :root {
    --bg: #f5f6f8;
    --card: #ffffff;
    --line: #e3e6ea;
    --text: #1d2430;
    --dim: #6b7686;
    --accent: #3d5afe;
    --ok: #1c8c56;
    --wait: #b26a00;
    --bad: #c33c3c;
    --tint: #eef1ff;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, sans-serif;
  }
  a { color: inherit; text-decoration: none; }
  .topbar {
    background: var(--card);
    border-bottom: 1px solid var(--line);
    padding: 0.75rem 1.5rem;
    display: flex;
    align-items: center;
    gap: 1rem;
    flex-wrap: wrap;
  }
  .brand { font-weight: 650; letter-spacing: -0.01em; font-size: 1.05rem; }
  .brand span { color: var(--accent); }
  .switcher { margin-left: auto; display: flex; align-items: center; gap: 0.6rem; flex-wrap: wrap; }
  .switcher select { min-width: 13rem; }
  main { padding: 1.75rem 1.5rem 3rem; max-width: 60rem; margin: 0 auto; }
  h1 { font-size: 1.4rem; margin: 0 0 0.25rem; letter-spacing: -0.015em; }
  h2 { font-size: 0.95rem; margin: 0 0 0.9rem; }
  .sub { color: var(--dim); margin: 0 0 1.5rem; }
  .card {
    background: var(--card);
    border: 1px solid var(--line);
    border-radius: 10px;
    padding: 1.1rem 1.25rem;
    margin-bottom: 1rem;
  }
  .tickets { background: var(--card); border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
  .ticket {
    display: flex;
    align-items: center;
    gap: 0.9rem;
    padding: 0.85rem 1.25rem;
    border-bottom: 1px solid var(--line);
  }
  .ticket:last-child { border-bottom: 0; }
  .ticket:hover { background: var(--tint); }
  .ticket .subject { font-weight: 550; }
  .ticket .meta { color: var(--dim); font-size: 0.85rem; }
  .ticket .right { margin-left: auto; display: flex; align-items: center; gap: 0.6rem; }
  .avatar {
    width: 2rem; height: 2rem; border-radius: 50%;
    background: var(--tint); color: var(--accent);
    display: grid; place-items: center;
    font-size: 0.75rem; font-weight: 650; letter-spacing: 0.02em;
    flex: none;
  }
  .chip {
    display: inline-block; padding: 0.12rem 0.6rem; border-radius: 999px;
    font-size: 0.75rem; font-weight: 550; border: 1px solid var(--line); color: var(--dim);
    white-space: nowrap;
  }
  .chip.open { color: var(--accent); border-color: #c6cffb; background: var(--tint); }
  .chip.escalated, .chip.completed, .chip.can { color: var(--ok); border-color: #bce3ce; background: #eefaf3; }
  .chip.waiting, .chip.pending, .chip.polling { color: var(--wait); border-color: #f0d9a8; background: #fdf6e7; }
  .chip.failed, .chip.unwinding, .chip.cancelled, .chip.cancelling { color: var(--bad); border-color: #f0c4c4; background: #fdeeee; }
  .tabs { display: flex; gap: 0.4rem; margin-bottom: 1rem; }
  .tabs a { padding: 0.35rem 0.85rem; border-radius: 999px; color: var(--dim); font-size: 0.9rem; }
  .tabs a.on { background: var(--card); color: var(--text); border: 1px solid var(--line); font-weight: 550; }
  button {
    font: inherit; font-weight: 550;
    color: var(--text); background: var(--card);
    border: 1px solid var(--line); border-radius: 7px;
    padding: 0.45rem 0.9rem; cursor: pointer;
  }
  button:hover { border-color: var(--accent); }
  button.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  button.primary:hover { filter: brightness(1.08); }
  button.danger { color: var(--bad); border-color: #f0c4c4; }
  button:disabled, button:disabled:hover {
    color: var(--dim); border-color: var(--line); background: var(--bg);
    cursor: not-allowed;
  }
  input, select, textarea {
    font: inherit; color: var(--text); background: var(--card);
    border: 1px solid var(--line); border-radius: 7px;
    padding: 0.45rem 0.6rem; width: 100%;
  }
  textarea { min-height: 4.5rem; resize: vertical; }
  label { display: block; font-size: 0.82rem; color: var(--dim); margin: 0 0 0.35rem; font-weight: 550; }
  .row { display: flex; gap: 0.6rem; align-items: center; flex-wrap: wrap; }
  .flash { padding: 0.7rem 1rem; border-radius: 8px; margin-bottom: 1rem; background: var(--tint); border: 1px solid #c6cffb; }
  .flash.error { background: #fdeeee; border-color: #f0c4c4; color: var(--bad); }
  .feed { list-style: none; margin: 0; padding: 0; }
  .feed li { display: flex; gap: 0.75rem; padding: 0.6rem 0; border-bottom: 1px solid var(--line); }
  .feed li:last-child { border-bottom: 0; }
  .feed .when { color: var(--dim); font-size: 0.82rem; margin-left: auto; white-space: nowrap; }
  .empty { color: var(--dim); padding: 1.25rem; }
  .back { color: var(--dim); font-size: 0.88rem; display: inline-block; margin-bottom: 0.75rem; }
  .back:hover { color: var(--accent); }
  details { margin-top: 1rem; }
  summary { cursor: pointer; color: var(--dim); font-size: 0.85rem; }
  details table { width: 100%; border-collapse: collapse; margin-top: 0.75rem; }
  details td { padding: 0.35rem 0.6rem 0.35rem 0; border-bottom: 1px solid var(--line); vertical-align: top; }
  .mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.8rem; }
  .value { color: var(--dim); white-space: pre-wrap; word-break: break-word; }
  """

  def root(assigns) do
    assigns = assign(assigns, :stylesheet, @stylesheet)

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <.live_title default="Helpdesk">{assigns[:page_title]}</.live_title>
        {Phoenix.HTML.raw("<style>" <> @stylesheet <> "</style>")}
        <script src={~p"/vendor/phoenix/phoenix.min.js"}>
        </script>
        <script src={~p"/vendor/live_view/phoenix_live_view.min.js"}>
        </script>
        <script>
          const token = document.querySelector("meta[name='csrf-token']").content
          const socket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
            params: {_csrf_token: token}
          })
          socket.connect()
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <div class="topbar">
      <div class="brand">help<span>desk</span></div>

      <.switcher
        organisations={@organisations}
        organisation={@organisation}
        people={@people}
        actor={@actor}
      />
    </div>

    <main>
      <div :if={Phoenix.Flash.get(@flash, :info)} class="flash">
        {Phoenix.Flash.get(@flash, :info)}
      </div>
      <div :if={Phoenix.Flash.get(@flash, :error)} class="flash error">
        {Phoenix.Flash.get(@flash, :error)}
      </div>

      {@inner_content}
    </main>
    """
  end
end
