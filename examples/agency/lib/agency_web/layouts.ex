defmodule AgencyWeb.Layouts do
  @moduledoc """
  The application's chrome: the document, the top bar, and the whole stylesheet.

  The style lives here as a string rather than in an asset pipeline, so the example runs with
  nothing built.
  """

  use AgencyWeb, :html

  @stylesheet """
  :root {
    --paper: #EDEEE9; --surface: #F7F8F4; --sunk: #E3E5DE;
    --ink: #171C1A; --ink-2: #58635D; --ink-3: #8A948D;
    --rule: #CFD4CB; --rule-2: #DFE3DA;
    --accent: #0F5257; --accent-wash: #DCE8E6;
    --live: #96620E; --live-wash: #F3E7CF;
    --stop: #8F3123; --stop-wash: #F3DCD7;
    --f-display: ui-serif, "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
    --f-ui: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
    --f-data: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --paper: #101413; --surface: #171D1B; --sunk: #0B0F0E;
      --ink: #E7EBE6; --ink-2: #99A39B; --ink-3: #6B756E;
      --rule: #2B342F; --rule-2: #222A26;
      --accent: #59B7A9; --accent-wash: #14312E;
      --live: #D3A24A; --live-wash: #33280F;
      --stop: #D5745C; --stop-wash: #351A14;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--paper); color: var(--ink);
    font-family: var(--f-ui); font-size: 15px; line-height: 1.5;
    -webkit-font-smoothing: antialiased;
  }
  a { color: inherit; }
  .eyebrow {
    font-family: var(--f-data); font-size: 10px; letter-spacing: 0.14em;
    text-transform: uppercase; color: var(--ink-3);
  }
  .num { font-family: var(--f-data); font-variant-numeric: tabular-nums; }
  .topbar {
    display: flex; align-items: center; justify-content: space-between;
    gap: 16px; flex-wrap: wrap;
    padding: 12px 24px; border-bottom: 1px solid var(--rule);
    background: var(--surface);
  }
  .brand { display: flex; align-items: baseline; gap: 10px; }
  .brand .mark { font-family: var(--f-display); font-size: 19px; font-weight: 600; letter-spacing: -0.01em; }
  .brand .desk { color: var(--ink-3); font-size: 13px; }
  .topnav { display: flex; gap: 18px; font-size: 13px; }
  .topnav a { color: var(--ink-2); text-decoration: none; }
  .topnav a:hover { color: var(--accent); }
  .whoami { display: flex; align-items: center; gap: 10px; font-size: 13px; color: var(--ink-2); }
  .avatar {
    width: 28px; height: 28px; border-radius: 50%; background: var(--accent-wash);
    color: var(--accent); display: grid; place-items: center;
    font-size: 11.5px; font-weight: 600; letter-spacing: 0.02em;
  }
  .shell {
    display: grid;
    grid-template-columns: 268px minmax(0, 1fr) 320px;
    gap: 0; align-items: start;
    min-height: 70vh;
  }
  @media (max-width: 1180px) {
    .shell { grid-template-columns: 240px minmax(0, 1fr); }
    .aside { grid-column: 1 / -1; border-left: none; border-top: 1px solid var(--rule); }
  }
  @media (max-width: 820px) {
    .shell { grid-template-columns: minmax(0, 1fr); }
    .rail { border-right: none; border-bottom: 1px solid var(--rule); }
  }
  .rail { border-right: 1px solid var(--rule); background: var(--surface); }
  .main { padding: 24px 28px 60px; min-width: 0; }
  .aside { border-left: 1px solid var(--rule); background: var(--surface); min-height: 100%; }
  .rail-head {
    padding: 13px 16px 11px; border-bottom: 1px solid var(--rule);
    display: flex; justify-content: space-between; align-items: baseline;
  }
  button.sign {
    font-family: var(--f-data); font-size: 10px; letter-spacing: 0.06em;
    text-transform: uppercase; padding: 3px 7px; border-radius: 2px;
    border: 1px solid var(--rule); background: none; color: var(--ink-3); cursor: pointer;
  }
  button.sign:hover { border-color: var(--accent); color: var(--accent); }
  .newform {
    display: flex; flex-direction: column; gap: 7px;
    padding: 13px 15px; border-bottom: 1px solid var(--rule); background: var(--paper);
  }
  .newform input, .newform select {
    font: inherit; font-size: 13.5px; padding: 7px 9px; width: 100%;
    border: 1px solid var(--rule); border-radius: 2px;
    background: var(--surface); color: var(--ink);
  }
  .newform input:focus-visible, .newform select:focus-visible {
    outline: 2px solid var(--accent); outline-offset: -1px;
  }
  .newform button.do { text-align: center; margin-top: 2px; }
  .lst {
    display: block; width: 100%; text-align: left; background: none;
    border: none; border-bottom: 1px solid var(--rule-2); border-left: 3px solid transparent;
    padding: 12px 15px; cursor: pointer; font: inherit; color: inherit;
  }
  .lst:hover { background: var(--paper); }
  .lst.on { background: var(--paper); border-left-color: var(--accent); }
  .lst:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
  .lst .addr { font-family: var(--f-display); font-size: 15.5px; font-weight: 600; line-height: 1.2; }
  .lst .sub { font-size: 12.5px; color: var(--ink-3); margin-top: 2px; }
  .lst .foot { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; margin-top: 7px; }
  .lst .amt { font-family: var(--f-data); font-size: 12.5px; font-variant-numeric: tabular-nums; color: var(--ink-2); }
  .pill {
    font-family: var(--f-data); font-size: 10px; letter-spacing: 0.06em;
    text-transform: uppercase; padding: 3px 7px; border-radius: 2px;
    border: 1px solid var(--rule); color: var(--ink-3); white-space: nowrap;
  }
  .pill.act { border-color: var(--live); color: var(--live); background: var(--live-wash); }
  .pill.ok { border-color: var(--accent); color: var(--accent); background: var(--accent-wash); }
  .pill.bad { border-color: var(--stop); color: var(--stop); background: var(--stop-wash); }
  .lh { display: flex; flex-wrap: wrap; gap: 14px 28px; align-items: flex-end; justify-content: space-between; }
  .lh h1 {
    font-family: var(--f-display); font-size: clamp(25px, 3vw, 34px);
    line-height: 1.08; font-weight: 600; letter-spacing: -0.015em; margin: 5px 0 0;
  }
  .lh .meta { color: var(--ink-2); font-size: 13.5px; margin-top: 6px; }
  .headline { text-align: right; font-family: var(--f-data); font-variant-numeric: tabular-nums; }
  .headline .big { font-size: 25px; letter-spacing: -0.01em; }
  .headline .cap { font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--ink-3); }
  .prog {
    display: flex; flex-wrap: wrap; gap: 2px; margin: 22px 0 26px;
    border: 1px solid var(--rule); background: var(--surface); border-radius: 2px; overflow: hidden;
  }
  .prog .st { flex: 1 1 96px; padding: 9px 11px; border-right: 1px solid var(--rule-2); min-width: 0; }
  .prog .st:last-child { border-right: none; }
  .prog .st .lab { font-size: 12.5px; color: var(--ink-3); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .prog .st .when { font-family: var(--f-data); font-size: 10.5px; color: var(--ink-3); margin-top: 2px; }
  .prog .st.done { background: var(--paper); }
  .prog .st.done .lab { color: var(--ink-2); }
  .prog .st.now { background: var(--live-wash); box-shadow: inset 0 -3px 0 var(--live); }
  .prog .st.now .lab { color: var(--ink); font-weight: 600; }
  .prog .st.now .when { color: var(--live); }
  .prog .st.gone { background: var(--stop-wash); box-shadow: inset 0 -3px 0 var(--stop); }
  .prog .st.gone .lab { color: var(--stop); }
  .card { border: 1px solid var(--rule); background: var(--surface); border-radius: 2px; margin-bottom: 20px; }
  .card > header {
    padding: 11px 16px; border-bottom: 1px solid var(--rule);
    display: flex; justify-content: space-between; align-items: center; gap: 12px;
  }
  .card > header h3 { margin: 0; font-family: var(--f-display); font-size: 16px; font-weight: 600; }
  .card .pad { padding: 16px; }
  .card.now { border-color: var(--live); }
  .card.now > header { background: var(--live-wash); border-bottom-color: var(--live); }
  .card.gone { border-color: var(--stop); border-style: dashed; }
  .tbl { width: 100%; border-collapse: collapse; font-size: 14px; }
  .tbl th {
    text-align: left; font-family: var(--f-data); font-size: 10px; letter-spacing: 0.1em;
    text-transform: uppercase; color: var(--ink-3); font-weight: 500;
    padding: 9px 16px; border-bottom: 1px solid var(--rule);
  }
  .tbl td { padding: 11px 16px; border-bottom: 1px solid var(--rule-2); vertical-align: top; }
  .tbl tr:last-child td { border-bottom: none; }
  .tbl .who { font-weight: 600; }
  .tbl .fin { font-size: 12.5px; color: var(--ink-3); }
  .tbl .amt { font-family: var(--f-data); font-variant-numeric: tabular-nums; }
  .tbl tr.out td { opacity: 0.5; }
  .tbl tr.out .amt { text-decoration: line-through; }
  .tbl tr.win { background: var(--accent-wash); }
  .tblwrap { overflow-x: auto; }
  .acts { display: flex; flex-direction: column; gap: 8px; }
  .offerform { display: flex; gap: 8px; margin-top: 12px; flex-wrap: wrap; }
  .offerform input {
    font: inherit; font-size: 13.5px; padding: 8px 10px; flex: 1; min-width: 120px;
    border: 1px solid var(--rule); border-radius: 2px;
    background: var(--surface); color: var(--ink);
  }
  .offerform button.do { width: auto; text-align: center; }
  button.do {
    font: inherit; font-size: 14px; text-align: left; padding: 10px 13px;
    border: 1px solid var(--rule); background: var(--paper); color: var(--ink);
    border-radius: 2px; cursor: pointer; transition: border-color 120ms, background 120ms; width: 100%;
  }
  button.do:hover { border-color: var(--accent); background: var(--accent-wash); }
  button.do:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  button.do.key { border-color: var(--accent); border-left-width: 3px; }
  button.do.no { color: var(--stop); }
  button.do.no:hover { border-color: var(--stop); background: var(--stop-wash); }
  button.do .hint { display: block; font-size: 12px; color: var(--ink-3); margin-top: 3px; }
  .grp {
    font-family: var(--f-data); font-size: 10px; letter-spacing: 0.1em; text-transform: uppercase;
    color: var(--ink-3); margin: 12px 0 2px; padding-bottom: 3px; border-bottom: 1px dotted var(--rule);
  }
  .grp:first-child { margin-top: 0; }
  .asec { border-bottom: 1px solid var(--rule); }
  .asec > header { padding: 12px 16px 9px; display: flex; justify-content: space-between; align-items: baseline; }
  .row { display: flex; justify-content: space-between; gap: 12px; align-items: baseline; padding: 8px 16px; font-size: 13.5px; border-top: 1px solid var(--rule-2); }
  .row .k { color: var(--ink-2); }
  .row .k small { display: block; color: var(--ink-3); font-size: 11.5px; }
  .row .v { font-family: var(--f-data); font-variant-numeric: tabular-nums; white-space: nowrap; }
  .row .v.ok { color: var(--accent); }
  .row .v.bad { color: var(--stop); }
  .row .v.wait { color: var(--live); }
  .money-hero { padding: 14px 16px 16px; }
  .money-hero .big { font-family: var(--f-data); font-size: 27px; font-variant-numeric: tabular-nums; letter-spacing: -0.01em; }
  .money-hero .cap { color: var(--ink-2); font-size: 13px; margin-top: 4px; }
  .feed { list-style: none; margin: 0; padding: 0; max-height: 300px; overflow-y: auto; }
  .feed li { display: grid; grid-template-columns: 62px minmax(0, 1fr); gap: 10px; padding: 8px 16px; border-top: 1px solid var(--rule-2); font-size: 13px; }
  .feed time { font-family: var(--f-data); font-size: 11.5px; color: var(--ink-3); }
  .feed .txt { color: var(--ink-2); }
  .feed .txt b { color: var(--ink); font-weight: 600; }
  .feed li.bad .txt b { color: var(--stop); }
  .empty { padding: 16px; color: var(--ink-3); font-size: 13.5px; }
  .chk { display: flex; flex-direction: column; }
  .chk .item { display: flex; gap: 10px; align-items: baseline; padding: 9px 16px; border-top: 1px solid var(--rule-2); font-size: 13.5px; }
  .chk .item:first-child { border-top: none; }
  .chk .box { font-family: var(--f-data); font-size: 12px; color: var(--ink-3); flex: none; }
  .chk .item.on .box { color: var(--accent); }
  .chk .item.off .box { color: var(--stop); }
  .chk .item.on .lb { color: var(--ink-2); }
  .chk .lb { color: var(--ink); }
  .hist { padding: 13px 16px; border-top: 1px solid var(--rule-2); font-size: 13.5px; }
  .hist:first-child { border-top: none; }
  .hist .hh { display: flex; justify-content: space-between; gap: 10px; align-items: baseline; }
  .hist .who { font-family: var(--f-display); font-size: 15px; font-weight: 600; }
  .hist .amt { font-family: var(--f-data); font-variant-numeric: tabular-nums; color: var(--ink-3); text-decoration: line-through; }
  .hist .why { color: var(--ink-2); margin-top: 4px; }
  .banner { padding: 12px 16px; background: var(--stop-wash); border: 1px solid var(--stop); border-radius: 2px; margin-bottom: 20px; font-size: 14px; }
  .banner b { color: var(--stop); }
  .flash { padding: 12px 16px; background: var(--accent-wash); border: 1px solid var(--accent); border-radius: 2px; margin-bottom: 20px; font-size: 14px; }
  .flash.error { background: var(--stop-wash); border-color: var(--stop); }
  .console { padding: 24px 28px 60px; max-width: 1180px; }
  .console h1 { font-family: var(--f-display); font-size: 26px; font-weight: 600; margin: 0 0 4px; }
  .console-grid { display: grid; grid-template-columns: minmax(0, 1fr) 380px; gap: 20px; align-items: start; }
  @media (max-width: 980px) { .console-grid { grid-template-columns: minmax(0, 1fr); } }
  .filters { display: flex; flex-wrap: wrap; gap: 6px; margin: 14px 0 18px; }
  .filters button {
    font: inherit; font-family: var(--f-data); font-size: 11.5px; letter-spacing: 0.04em;
    padding: 5px 10px; border-radius: 2px; border: 1px solid var(--rule); background: var(--surface);
    color: var(--ink-2); cursor: pointer;
  }
  .filters button:hover { border-color: var(--accent); color: var(--accent); }
  .filters button.on { border-color: var(--accent); background: var(--accent-wash); color: var(--accent); }
  .wf-row { cursor: pointer; }
  .wf-row:hover td { background: var(--paper); }
  .wf-row.on td { background: var(--accent-wash); }
  .wf-row .mod { font-weight: 600; }
  .mono-id { font-family: var(--f-data); color: var(--ink-3); font-size: 12px; }
  .tree { list-style: none; margin: 0; padding: 0; }
  .tree ul { list-style: none; margin: 0; padding: 0 0 0 20px; }
  .tree li { border-left: 1px solid var(--rule-2); }
  .tree li:last-child { border-left-color: transparent; }
  .tree-row {
    display: flex; align-items: center; gap: 8px; width: 100%; text-align: left;
    font: inherit; font-size: 13px; padding: 6px 10px; border: none; background: none;
    color: inherit; cursor: pointer; border-radius: 2px;
  }
  .tree-row:hover { background: var(--paper); }
  .tree-row.on { background: var(--accent-wash); }
  .tree-row .mod { font-family: var(--f-data); }
  .tree-row .via { color: var(--ink-3); font-size: 11.5px; }
  .detail-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; flex-wrap: wrap; }
  .detail-head h2 { font-family: var(--f-display); font-size: 20px; margin: 0 0 2px; }
  .detail-head .parent { font-size: 12.5px; color: var(--ink-3); margin-top: 4px; }
  .detail-head .parent button { font: inherit; color: var(--accent); background: none; border: none; padding: 0; cursor: pointer; text-decoration: underline; }
  .steps { list-style: none; margin: 0; padding: 0; }
  .steps li { padding: 10px 16px; border-top: 1px solid var(--rule-2); }
  .steps li:first-child { border-top: none; }
  .steps .lab { font-family: var(--f-data); font-size: 13px; font-weight: 600; }
  .steps details { margin-top: 4px; }
  .steps summary { font-family: var(--f-data); font-size: 12.5px; color: var(--ink-2); cursor: pointer; }
  .steps pre { font-family: var(--f-data); font-size: 12px; background: var(--sunk); padding: 10px 12px; border-radius: 2px; overflow-x: auto; margin: 6px 0 0; white-space: pre-wrap; word-break: break-word; }
  .parked { padding: 12px 16px; font-size: 13.5px; }
  .parked .sig { font-family: var(--f-data); font-weight: 600; }
  .parked .dl { color: var(--ink-3); font-size: 12.5px; margin-left: 8px; }
  .note { padding: 10px 16px; font-size: 12.5px; color: var(--ink-3); border-top: 1px solid var(--rule-2); }
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
        <.live_title default="Ray &amp; Cole">{assigns[:page_title]}</.live_title>
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
          window.liveSocket = socket
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
      <div class="brand">
        <span class="mark">Ray &amp; Cole</span>
        <span class="desk">Sales desk</span>
      </div>
      <nav class="topnav">
        <.link navigate={~p"/"}>Sales desk</.link>
        <.link navigate={~p"/console"}>Workflow console</.link>
      </nav>
      <div class="whoami">
        <span class="avatar">PR</span>
        <span>Priya Chandra &middot; Sales agent</span>
      </div>
    </div>

    <div :if={Phoenix.Flash.get(@flash, :info)} class="flash" style="margin:16px 24px 0">
      {Phoenix.Flash.get(@flash, :info)}
    </div>
    <div :if={Phoenix.Flash.get(@flash, :error)} class="flash error" style="margin:16px 24px 0">
      {Phoenix.Flash.get(@flash, :error)}
    </div>

    {@inner_content}
    """
  end
end
