defmodule HelpdeskWeb.Layouts do
  @moduledoc """
  The console's chrome: the document, the header, and the whole stylesheet.

  The style lives here as a string rather than in an asset pipeline, so the example runs with
  `mix phx.server` and nothing else.
  """

  use HelpdeskWeb, :html

  @stylesheet """
  :root {
    --bg: #0f1115;
    --panel: #171a21;
    --line: #262b35;
    --text: #d7dae0;
    --dim: #838b99;
    --accent: #ff7043;
    --ok: #6bd08a;
    --wait: #e3c05c;
    --bad: #e5695f;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font: 14px/1.5 ui-sans-serif, system-ui, sans-serif;
  }
  a { color: inherit; }
  header {
    border-bottom: 1px solid var(--line);
    padding: 0.9rem 1.4rem;
    display: flex;
    align-items: baseline;
    gap: 1rem;
  }
  header b { color: var(--accent); letter-spacing: 0.02em; }
  header span { color: var(--dim); font-size: 0.8rem; }
  main { padding: 1.4rem; max-width: 76rem; margin: 0 auto; }
  h1 { font-size: 1.05rem; margin: 0 0 1rem; }
  h2 { font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--dim); margin: 0 0 0.7rem; }
  .grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(21rem, 1fr)); }
  .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 6px; padding: 1rem; }
  table { width: 100%; border-collapse: collapse; }
  th { text-align: left; font-weight: 500; color: var(--dim); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.06em; }
  th, td { padding: 0.4rem 0.6rem 0.4rem 0; border-bottom: 1px solid var(--line); vertical-align: top; }
  tr:last-child td { border-bottom: 0; }
  code, .mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.8rem; }
  .value { color: var(--dim); white-space: pre-wrap; word-break: break-word; }
  .chip { display: inline-block; padding: 0.1rem 0.5rem; border: 1px solid var(--line); border-radius: 999px; font-size: 0.72rem; letter-spacing: 0.04em; }
  .completed, .registered, .active { color: var(--ok); border-color: var(--ok); }
  .waiting, .polling, .pending, .recorded { color: var(--wait); border-color: var(--wait); }
  .failed, .cancelled, .unwinding, .cancelling { color: var(--bad); border-color: var(--bad); }
  button {
    font: inherit;
    color: var(--text);
    background: #1f242e;
    border: 1px solid var(--line);
    border-radius: 4px;
    padding: 0.35rem 0.8rem;
    cursor: pointer;
  }
  button:hover { border-color: var(--accent); }
  button:disabled, button:disabled:hover { color: var(--dim); border-color: var(--line); opacity: 0.45; cursor: not-allowed; }
  button.primary { border-color: var(--accent); color: var(--accent); }
  button.danger { border-color: var(--bad); color: var(--bad); }
  input, select {
    font: inherit;
    color: var(--text);
    background: #12151b;
    border: 1px solid var(--line);
    border-radius: 4px;
    padding: 0.35rem 0.5rem;
    width: 100%;
  }
  label { display: block; font-size: 0.75rem; color: var(--dim); margin: 0 0 0.6rem; }
  .row { display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; }
  .flash { padding: 0.6rem 1rem; border-radius: 4px; margin-bottom: 1rem; border: 1px solid var(--line); }
  .flash.error { border-color: var(--bad); color: var(--bad); }
  .hint { color: var(--dim); font-size: 0.8rem; margin: 0 0 0.8rem; }
  .empty { color: var(--dim); font-style: italic; }
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
        <.live_title default="helpdesk console">{assigns[:page_title]}</.live_title>
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
    <header>
      <b>helpdesk</b>
      <span>a magma console — every run below acts as one actor, in one tenant</span>
      <span style="margin-left:auto"><.link navigate={~p"/"}>the queue</.link></span>
    </header>

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

  @doc "A list of permissions as something to read."
  @spec permissions([atom()]) :: String.t()
  def permissions([]), do: "none"
  def permissions(held), do: Enum.map_join(held, ", ", &to_string/1)
end
