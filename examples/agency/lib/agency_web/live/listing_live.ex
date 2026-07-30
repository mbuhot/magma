defmodule AgencyWeb.ListingLive do
  @moduledoc """
  The agent's sales desk: one listing at a time, and whatever it is waiting on.

  Every button here delivers a signal to the workflow behind the listing, or moves a lender's,
  title office's or PEXA's state and lets the workflow notice — nothing is written straight
  into the domain's own rows. What is offered is read fresh from those rows and from the
  workflow's own parked waits on every render, so the screen never drifts from what actually
  happened.
  """

  use AgencyWeb, :live_view

  alias Agency.Sale
  alias AgencyWeb.ListingLive.Board
  alias AgencyWeb.Updates

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Updates.follow()

    {:ok, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: topic}, socket) do
    require Logger

    Logger.info(
      "DESK GOT #{topic} actions=#{inspect(socket.assigns.board && stage_actions(socket.assigns.board) |> length())}"
    )

    {:noreply, load(socket)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    listings = Board.listings()
    agency_agreement_id = params["id"] || listing_id_of(List.first(listings))

    {:noreply,
     socket
     |> assign(listings: listings, agency_agreement_id: agency_agreement_id)
     |> assign_new(:signing?, fn -> false end)
     |> load()}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/listings/#{id}")}
  end

  def handle_event("sign_listing", _params, socket) do
    {:noreply, assign(socket, signing?: !socket.assigns.signing?)}
  end

  def handle_event("start_listing", params, socket) do
    agreement = Sale.sign_listing!(params)

    {:noreply,
     socket
     |> assign(signing?: false)
     |> push_patch(to: ~p"/listings/#{agreement.id}")}
  end

  def handle_event("receive_document", %{"kind" => kind}, socket) do
    instruct(socket, fn -> Sale.hand_over_document!(listing(socket), kind) end)
  end

  def handle_event("launch_campaign", _params, socket) do
    instruct(socket, fn -> Sale.launch_campaign!(listing(socket)) end)
  end

  def handle_event("withdraw_listing", _params, socket) do
    instruct(socket, fn -> Sale.withdraw_listing!(listing(socket)) end)
  end

  def handle_event("re_approach", %{"buyer_id" => buyer_id}, socket) do
    instruct(socket, fn -> Sale.re_approach!(listing(socket), buyer_id) end)
  end

  def handle_event("relaunch_campaign", _params, socket) do
    instruct(socket, fn -> Sale.relaunch_campaign!(listing(socket)) end)
  end

  def handle_event("receive_offer", params, socket) do
    Sale.receive_offer!(Map.put(params, "agency_agreement_id", listing(socket)))

    {:noreply, load(socket)}
  end

  def handle_event("close_offers", _params, socket) do
    instruct(socket, fn -> Sale.close_offers!(listing(socket)) end)
  end

  def handle_event("select_offer", %{"offer_id" => offer_id}, socket) do
    instruct(socket, fn -> Sale.select_offer!(listing(socket), offer_id) end)
  end

  def handle_event("accept_offer", %{"offer_id" => offer_id}, socket) do
    instruct(socket, fn -> Sale.respond_to_offer!(offer_id, :accept) end)
  end

  def handle_event("counter_offer", %{"offer_id" => offer_id, "amount" => amount}, socket) do
    case Integer.parse(amount) do
      {dollars, _rest} ->
        instruct(socket, fn ->
          Sale.respond_to_offer!(offer_id, :counter, %{amount: dollars * 100})
        end)

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("withdraw_offer", %{"offer_id" => offer_id}, socket) do
    instruct(socket, fn -> Sale.respond_to_offer!(offer_id, :withdraw) end)
  end

  def handle_event("sold_under_the_hammer", _params, socket) do
    instruct(socket, fn -> Sale.sell_under_the_hammer!(listing(socket)) end)
  end

  def handle_event("passed_in", _params, socket) do
    instruct(socket, fn -> Sale.pass_in!(listing(socket)) end)
  end

  def handle_event("rescind", %{"buyer_id" => buyer_id}, socket) do
    instruct(socket, fn -> Sale.rescind!(listing(socket), buyer_id) end)
  end

  def handle_event("finance_approved", _params, socket), do: move_finance(socket, :approved)
  def handle_event("finance_declined", _params, socket), do: move_finance(socket, :declined)

  def handle_event("inspection_satisfied", _params, socket),
    do: resolve_inspection(socket, :satisfied)

  def handle_event("inspection_failed", _params, socket), do: resolve_inspection(socket, :failed)
  def handle_event("title_clear", _params, socket), do: move_title(socket, :clear)
  def handle_event("title_encumbered", _params, socket), do: move_title(socket, :encumbered)

  def handle_event("settle", _params, socket) do
    instruct(socket, fn -> Sale.settle_contract!(socket.assigns.board.contract.id) end)
  end

  def handle_event("buyer_defaults", _params, socket) do
    instruct(socket, fn -> Sale.buyer_defaults!(socket.assigns.board.contract.id) end)
  end

  defp move_finance(socket, decision) do
    instruct(socket, fn -> Sale.record_finance!(socket.assigns.board.contract.id, decision) end)
  end

  defp move_title(socket, decision) do
    instruct(socket, fn -> Sale.record_title!(socket.assigns.board.contract.id, decision) end)
  end

  defp resolve_inspection(socket, decision) do
    instruct(socket, fn -> Sale.resolve_inspection!(listing(socket), decision) end)
  end

  defp listing(socket), do: socket.assigns.agency_agreement_id

  # An instruction that cannot land is the agent's news, not a dead page: the desk says so and
  # stays up, because the run it was meant for is still there to try again.
  defp instruct(socket, instruction) do
    instruction.()

    {:noreply, load(socket)}
  rescue
    error ->
      {:noreply, socket |> put_flash(:error, Exception.message(error)) |> load()}
  end

  defp listing_id_of(nil), do: nil
  defp listing_id_of(listing), do: listing.id

  defp load(socket) do
    case socket.assigns.agency_agreement_id do
      nil -> assign(socket, board: nil, page_title: "Sales desk")
      id -> assign(socket, board: Board.load(id), page_title: "Sales desk")
    end
  end

  defp buyer_position(buyer, board) do
    offer = Enum.find(board.offers, &(&1.buyer_id == buyer.id))
    label = position_label(buyer.register_status, offer)
    {label, offer}
  end

  defp position_label(:missed, _offer), do: "Not selected"
  defp position_label(:withdrew, _offer), do: "Withdrew"
  defp position_label(:rescinded, _offer), do: "Rescinded during cooling off"
  defp position_label(:defaulted, _offer), do: "Defaulted at settlement"
  defp position_label(:under_contract, _offer), do: "Holds the contract"
  defp position_label(:available, nil), do: "On the register"
  defp position_label(:available, %{status: :live}), do: "Offer on the table"
  defp position_label(:available, %{status: :countered}), do: "Countered, awaiting a reply"

  defp position_label(:available, %{status: :accepted}),
    do: "Accepted, awaiting the vendor's final choice"

  defp position_label(:available, %{status: :missed}), do: "Not selected"
  defp position_label(:available, %{status: :lapsed}), do: "Offer lapsed"
  defp position_label(:available, %{status: :withdrawn}), do: "Withdrew"
  defp position_label(:available, %{status: :superseded}), do: "Countered, waiting on a reply"

  defp stage_label(:prep), do: "Preparing"
  defp stage_label(:marketing), do: "On market"
  defp stage_label(:offers_open), do: "Offers open"
  defp stage_label(:offers_in), do: "Offers in"
  defp stage_label(:auction_day), do: "Auction"
  defp stage_label(:negotiating), do: "Negotiating"
  defp stage_label(:back_on_market), do: "Back on market"
  defp stage_label(:cooling), do: "Cooling off"
  defp stage_label(:conditions), do: "Conditions"
  defp stage_label(:awaiting_settlement), do: "Awaiting settlement"
  defp stage_label(:settled), do: "Settled"
  defp stage_label(:lapsed), do: "Ended"

  defp status_pill(:settled), do: {"ok", "Settled"}
  defp status_pill(:lapsed), do: {"bad", "Ended"}
  defp status_pill(:back_on_market), do: {"bad", "Back on market"}

  defp status_pill(stage) when stage in [:cooling, :conditions, :awaiting_settlement],
    do: {"ok", "Under contract"}

  defp status_pill(stage), do: {"act", stage_label(stage)}

  defp method_stage_word(:auction), do: "Auction"
  defp method_stage_word(:set_date), do: "Offers"
  defp method_stage_word(:treaty), do: "Negotiating"

  defp progress_steps(board) do
    method = board.agreement.sale_method
    ["Prepared", method_stage_word(method), "Exchanged", "Cooling off", "Conditions", "Settled"]
  end

  defp progress_index(:prep), do: 0
  defp progress_index(:marketing), do: 1

  defp progress_index(stage) when stage in [:offers_open, :offers_in, :auction_day, :negotiating],
    do: 1

  defp progress_index(:back_on_market), do: 1
  defp progress_index(:cooling), do: 3
  defp progress_index(:conditions), do: 4
  defp progress_index(:awaiting_settlement), do: 4
  defp progress_index(:settled), do: 5
  defp progress_index(:lapsed), do: 1

  defp progress_status(stage, index) do
    at = progress_index(stage)

    cond do
      stage == :lapsed and index == at -> "gone"
      index < at -> "done"
      index == at -> "now"
      true -> ""
    end
  end

  defp commission_hero(nil, board) do
    estimate = Sale.Money.commission(board.agreement.guide_price, board.agreement.commission_rate)
    {Board.money(estimate), "Estimated at the guide price"}
  end

  defp commission_hero(%{outcome: :disbursed} = commission, _board) do
    {Board.money(commission.amount),
     "Paid #{Calendar.strftime(commission.disbursed_at, "%d %b")}"}
  end

  defp commission_hero(%{outcome: :written_back} = commission, _board) do
    {Board.money(commission.amount), "Written back — this attempt fell through"}
  end

  defp commission_hero(%{payable_on: :on_unconditional} = commission, _board) do
    {Board.money(commission.amount), "Payable once the contract is unconditional"}
  end

  defp commission_hero(commission, board) do
    due = board.contract && Calendar.strftime(board.contract.settlement_date, "%d %b %Y")
    {Board.money(commission.amount), "Payable on settlement, due #{due}"}
  end

  defp requirements(board) do
    Enum.map(board.required_documents, fn kind ->
      {kind, Sale.DocumentKind.label(kind), MapSet.member?(board.received_documents, kind)}
    end)
  end

  defp cooling_policy(board), do: Sale.Jurisdiction.cooling_off(board.property.jurisdiction)

  defp when_at(datetime), do: Calendar.strftime(datetime, "%d %b %Y")

  defp active_negotiation(board) do
    board.offers
    |> Enum.filter(&(&1.status in [:live, :countered]))
    |> Enum.find(&Map.has_key?(board.workflows.negotiations, &1.id))
  end

  defp buyer_name(board, buyer_id), do: Enum.find(board.buyers, &(&1.id == buyer_id)).name

  defp condition_by_kind(board, kind), do: Enum.find(board.conditions, &(&1.kind == kind))

  defp headline(%{stage: stage} = board) when stage in [:back_on_market, :marketing, :lapsed],
    do: {Board.money(board.agreement.guide_price), "guide"}

  defp headline(%{contract: nil} = board),
    do: {Board.money(board.agreement.guide_price), "guide"}

  defp headline(board), do: {Board.money(board.contract.price), "under contract"}

  defp listing_stage(agency_agreement_id), do: Board.load(agency_agreement_id).stage

  defp jurisdictions,
    do: Sale.Jurisdiction.values() |> Enum.map(&{&1, Sale.Jurisdiction.label(&1)})

  defp sale_methods, do: Sale.SaleMethod.values() |> Enum.map(&{&1, Sale.SaleMethod.label(&1)})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="shell">
      <nav class="rail">
        <div class="rail-head">
          <span class="eyebrow">My listings</span>
          <button class="sign" phx-click="sign_listing">
            {if @signing?, do: "Cancel", else: "+ New"}
          </button>
        </div>

        <form :if={@signing?} id="new-listing" class="newform" phx-submit="start_listing">
          <input name="address" placeholder="Address" required />
          <input name="suburb" placeholder="Suburb" required />
          <select name="jurisdiction">
            <option :for={{value, label} <- jurisdictions()} value={value}>{label}</option>
          </select>
          <select name="sale_method">
            <option :for={{value, label} <- sale_methods()} value={value}>{label}</option>
          </select>
          <input name="vendor_name" placeholder="Vendor" required />
          <input
            name="guide_price_dollars"
            placeholder="Guide price"
            inputmode="numeric"
            required
          />
          <input name="commission_rate" value="2.2" aria-label="Commission rate" />
          <button class="do key" type="submit">Sign and put to market</button>
        </form>

        <div>
          <button
            :for={listing <- @listings}
            class={["lst", listing.id == @agency_agreement_id && "on"]}
            phx-click="select"
            phx-value-id={listing.id}
          >
            <div class="addr">{listing.property.address}</div>
            <div class="sub">{listing.property.suburb} &middot; {String.upcase(to_string(listing.property.jurisdiction))} &middot; {Sale.SaleMethod.label(listing.sale_method)}</div>
            <div class="foot">
              <span class="amt">{Board.money(listing.guide_price)} guide</span>
              <% {pill_class, pill_text} = status_pill(listing_stage(listing.id)) %>
              <span class={["pill", pill_class]}>{pill_text}</span>
            </div>
          </button>
        </div>
      </nav>

      <main :if={@board == nil} class="main">
        <p class="empty">
          No listings yet. Sign one on the left, or run <code>mix agency.seed</code>.
        </p>
      </main>

      <main :if={@board != nil} class="main">
        <div class="lh">
          <div>
            <div class="eyebrow">
              {@board.property.suburb} &middot; {Sale.Jurisdiction.label(@board.property.jurisdiction)} &middot; {Sale.SaleMethod.label(@board.agreement.sale_method)}
            </div>
            <h1>{@board.property.address}</h1>
            <div class="meta">
              Vendor {@board.agreement.vendor_name} &middot; {Decimal.to_string(@board.agreement.commission_rate)}% inc GST, payable {payable_word(@board.agreement.commission_trigger)}
            </div>
          </div>
          <% {headline_amount, headline_caption} = headline(@board) %>
          <div class="headline">
            <div class="big">{headline_amount}</div>
            <div class="cap">{headline_caption}</div>
          </div>
        </div>

        <div class="prog">
          <div :for={{label, index} <- Enum.with_index(progress_steps(@board))} class={["st", progress_status(@board.stage, index)]}>
            <div class="lab">{label}</div>
          </div>
        </div>

        <div :if={@board.history != []} class="banner">
          <b>The sale to {List.first(@board.history).buyer && List.first(@board.history).buyer.name} fell through.</b>
          {List.first(@board.history).reason}{forfeit_clause(List.first(@board.history))}.
          The contract and marketing still stand, so the register stays warm.
        </div>

        {stage_card(assigns)}

        <div :if={@board.offers != [] and @board.stage in [:offers_open, :offers_in, :negotiating, :auction_day]} class="card">
          <header>
            <h3>{if @board.agreement.sale_method == :auction, do: "Registered bidders", else: "Buyers"}</h3>
          </header>
          <div class="tblwrap">
            <table class="tbl">
              <thead><tr><th>Buyer</th><th>Amount</th><th>Position</th></tr></thead>
              <tbody>
                <tr :for={buyer <- @board.buyers}>
                  <% {label, offer} = buyer_position(buyer, @board) %>
                  <td><div class="who">{buyer.name}</div><div class="fin">{buyer.lender}</div></td>
                  <td class="amt">{offer && Board.money(offer.amount)}</td>
                  <td>{label}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div :if={@board.stage in [:conditions, :awaiting_settlement, :settled] and @board.contract} class="card">
          <header><h3>Conditions</h3></header>
          <div class="chk">
            <div :for={condition <- @board.conditions} class={["item", condition.status != :pending && "on"]}>
              <span class="box">{if condition.status == :pending, do: "[ ]", else: "[x]"}</span>
              <span class="lb">{Sale.ConditionKind.label(condition.kind)}</span>
            </div>
          </div>
        </div>

        <div :if={@board.history != []} class="card gone">
          <header><h3>Contracts that fell through</h3><span class="eyebrow">{length(@board.history)}</span></header>
          <div :for={past <- @board.history} class="hist">
            <div class="hh">
              <span class="who">{past.buyer && past.buyer.name}</span>
              <span class="amt">{past.contract && Board.money(past.contract.price)}</span>
            </div>
            <div class="why">
              {past.reason} on {when_at(past.attempt.closed_at)}
              {forfeit_clause(past)}
              &middot; commission {past.commission && Board.money(past.commission.amount)} {commission_outcome_words(past.commission)}
            </div>
          </div>
        </div>
      </main>

      <aside :if={@board != nil} class="aside">
        <div class="asec">
          <header>
            <span class="eyebrow">Your commission</span>
            <span class="eyebrow">{Decimal.to_string(@board.agreement.commission_rate)}%</span>
          </header>
          <% {hero_amount, hero_caption} = commission_hero(@board.commission, @board) %>
          <div class="money-hero">
            <div class="big">{hero_amount}</div>
            <div class="cap">{hero_caption}</div>
          </div>
          <div class="row"><span class="k">Sale price</span><span class="v">{(@board.contract && Board.money(@board.contract.price)) || "—"}</span></div>
          <div class="row"><span class="k">Deposit in trust</span><span class="v">{(@board.deposit && @board.deposit.status == :held && Board.money(@board.deposit.amount)) || "—"}</span></div>
          <div class="row"><span class="k">Paid to date</span><span class="v ok">{if @board.totals.paid > 0, do: Board.money(@board.totals.paid), else: "—"}</span></div>
          <div class="row"><span class="k">Written back</span><span class="v bad">{if @board.totals.written_back > 0, do: Board.money(@board.totals.written_back), else: "—"}</span></div>
          <div class="row"><span class="k">Forfeited to vendor</span><span class="v bad">{if @board.totals.forfeited > 0, do: Board.money(@board.totals.forfeited), else: "—"}</span></div>
        </div>

        <div class="asec">
          <header>
            <span class="eyebrow">{String.upcase(to_string(@board.property.jurisdiction))} requirements</span>
            <span class="eyebrow">{MapSet.size(@board.received_documents)} of {length(@board.required_documents)}</span>
          </header>
          <div class="chk">
            <div :for={{_kind, label, received} <- requirements(@board)} class={["item", received && "on"]}>
              <span class="box">{if received, do: "[x]", else: "[ ]"}</span>
              <span class="lb">{label}</span>
            </div>
          </div>
          <div class="row">
            <span class="k">Cooling off<small>{if @board.agreement.sale_method == :auction, do: "not applicable at auction", else: "from exchange"}</small></span>
            <span class="v">{cooling_policy(@board).business_days} bus. days</span>
          </div>
          <div class="row">
            <span class="k">Forfeit on rescission</span>
            <span class="v">{Decimal.mult(cooling_policy(@board).forfeit_rate, Decimal.new(100)) |> Decimal.normalize() |> Decimal.to_string()}%</span>
          </div>
        </div>

        <div class="asec">
          <header><span class="eyebrow">Activity</span></header>
          <ul class="feed">
            <li :for={{at, text} <- @board.feed}>
              <time>{when_at(at)}</time><span class="txt">{Phoenix.HTML.raw(text)}</span>
            </li>
          </ul>
          <p :if={@board.feed == []} class="empty">Nothing recorded yet.</p>
        </div>
      </aside>
    </div>
    """
  end

  defp finance_words(%{finance: :approved}), do: "Finance already approved"
  defp finance_words(%{finance: :declined}), do: "Finance declined last time"
  defp finance_words(%{finance: :cash}), do: "Cash purchase"

  defp finance_words(%{finance: :subject_to_finance, buyer: %{lender: nil}}),
    do: "Subject to finance"

  defp finance_words(%{finance: :subject_to_finance, buyer: buyer}),
    do: "Finance through #{buyer.lender}"

  defp payable_word(:on_settlement), do: "on settlement"
  defp payable_word(:on_unconditional), do: "on unconditional"

  defp forfeit_clause(%{forfeit: forfeit}) when is_integer(forfeit) and forfeit > 0,
    do: " — #{Board.money(forfeit)} forfeited"

  defp forfeit_clause(%{deposit: %{status: :forfeited, forfeited_amount: amount}})
       when is_integer(amount) and amount > 0,
       do: " — #{Board.money(amount)} forfeited"

  defp forfeit_clause(_past), do: ""

  defp commission_outcome_words(nil), do: ""
  defp commission_outcome_words(%{outcome: :written_back}), do: "written back"

  defp commission_outcome_words(%{outcome: :disbursed, paid_from: "forfeited deposit"}),
    do: "paid from the forfeited deposit"

  defp commission_outcome_words(%{outcome: :disbursed}), do: "paid"

  defp stage_card(assigns) do
    ~H"""
    <div class={["card", stage_key?(@board.stage) && "now"]}>
      <header>
        <h3>{stage_title(@board)}</h3>
        <span :if={stage_actions(@board) != []} class="pill act">Needs you</span>
      </header>
      <div class="pad">
        <div style="color:var(--ink-2);font-size:13.5px;margin-bottom:14px">{stage_sub(@board)}</div>
        <div :if={stage_actions(@board) != []} class="acts">
          {stage_action_buttons(assigns)}
        </div>

        <form
          :if={@board.stage in [:offers_open, :auction_day, :negotiating]}
          id="new-offer"
          class="offerform"
          phx-submit="receive_offer"
        >
          <input name="buyer_name" placeholder="Buyer" required />
          <input name="lender" placeholder="Lender, or cash" />
          <input name="amount_dollars" placeholder="Offer" inputmode="numeric" required />
          <button class="do" type="submit">Take the offer</button>
        </form>
      </div>
    </div>
    """
  end

  defp stage_key?(stage), do: stage not in [:settled, :lapsed]

  defp stage_title(%{stage: :prep}), do: "Waiting on the vendor's solicitor"
  defp stage_title(%{stage: :marketing}), do: "Ready to go to market"
  defp stage_title(%{stage: :offers_open}), do: "Offers are open"
  defp stage_title(%{stage: :offers_in}), do: "Work the offers"
  defp stage_title(%{stage: :auction_day}), do: "Auction day"

  defp stage_title(%{stage: :negotiating} = board) do
    if active_negotiation(board), do: "Negotiating", else: "Choose the buyer"
  end

  defp stage_title(%{stage: :back_on_market}), do: "Re-approach the underbidders"

  defp stage_title(%{stage: :cooling} = board),
    do: "Cooling off — ends #{when_at(board.contract.exchanged_at)}"

  defp stage_title(%{stage: :conditions}), do: "Conditions to satisfy"

  defp stage_title(%{stage: :awaiting_settlement} = board),
    do: "Settlement due #{when_at(board.contract.settlement_date)}"

  defp stage_title(%{stage: :settled}), do: "Settled"
  defp stage_title(%{stage: :lapsed}), do: "Listing ended"

  defp stage_sub(%{stage: :prep}),
    do: "The property can't go to market until the required documents arrive."

  defp stage_sub(%{stage: :marketing}), do: "Launch the campaign, or the vendor can withdraw."

  defp stage_sub(%{stage: :offers_open} = board),
    do: "#{length(board.buyers)} buyers have the contract."

  defp stage_sub(%{stage: :offers_in}),
    do: "Counter or accept each buyer — they move independently."

  defp stage_sub(%{stage: :auction_day} = board) do
    highest = Enum.find(board.offers, &(&1.status == :live))
    "Highest bid on record: #{highest && Board.money(highest.amount)}."
  end

  defp stage_sub(%{stage: :negotiating} = board) do
    if active_negotiation(board),
      do: "The vendor and buyer are still bargaining over this offer.",
      else: "Every buyer has answered — pick who wins."
  end

  defp stage_sub(%{stage: :back_on_market}),
    do: "The contract fell through. Your buyer register is still warm."

  defp stage_sub(%{stage: :cooling}), do: "The buyer may still rescind before the period ends."
  defp stage_sub(%{stage: :conditions}), do: "The sale is not secure until all three clear."
  defp stage_sub(%{stage: :awaiting_settlement}), do: "Booked with the parties' conveyancers."
  defp stage_sub(%{stage: :settled}), do: "Nothing further needed."
  defp stage_sub(%{stage: :lapsed}), do: "A fresh listing is needed to relaunch this property."

  defp stage_actions(%{stage: :prep} = board) do
    board.required_documents
    |> Enum.filter(&awaited?(board, &1))
    |> Enum.map(
      &%{
        label: "#{Sale.DocumentKind.label(&1)} received",
        event: "receive_document",
        values: %{"kind" => &1},
        key: false,
        danger: false
      }
    )
  end

  # The gate is the authority on which document it is waiting for, and it takes them one at a
  # time, so what the agent is offered is what the gate can presently accept.
  defp awaited?(%{workflows: %{engagement_id: nil}}, _kind), do: false

  defp awaited?(%{workflows: %{engagement_id: engagement_id}}, kind) do
    engagement_id
    |> Sale.Runs.compliance_gate_id()
    |> Sale.Runs.waiting_on?("document.#{kind}")
  end

  defp stage_actions(%{stage: :marketing}) do
    [
      %{
        label: "Launch the campaign",
        event: "launch_campaign",
        values: %{},
        key: true,
        danger: false
      },
      %{
        label: "Vendor withdraws",
        event: "withdraw_listing",
        values: %{},
        key: false,
        danger: true
      }
    ]
  end

  defp stage_actions(%{stage: :offers_open} = board) do
    [
      %{
        label: "Close offers now",
        event: "close_offers",
        values: %{},
        key: true,
        danger: false,
        hint: "#{length(board.offers)} offers received"
      }
    ]
  end

  defp stage_actions(%{stage: :offers_in} = board) do
    board.offers
    |> Enum.filter(&(&1.status in [:live, :countered]))
    |> Enum.filter(&Map.has_key?(board.workflows.negotiations, &1.id))
    |> Enum.flat_map(&offer_actions(board, &1))
  end

  defp stage_actions(%{stage: :negotiating} = board) do
    case active_negotiation(board) do
      nil ->
        board.offers
        |> Enum.filter(&(&1.status == :accepted))
        |> Enum.sort_by(& &1.amount, :desc)
        |> Enum.with_index()
        |> Enum.map(fn {offer, index} ->
          %{
            label: "Accept #{buyer_name(board, offer.buyer_id)} at #{Board.money(offer.amount)}",
            event: "select_offer",
            values: %{"offer_id" => offer.id},
            key: index == 0,
            danger: false
          }
        end)

      offer ->
        offer_actions(board, offer)
    end
  end

  defp stage_actions(%{stage: :auction_day} = board) do
    highest = Enum.find(board.offers, &(&1.status == :live))

    [
      %{
        label: "Sold under the hammer at #{Board.money(highest.amount)}",
        event: "sold_under_the_hammer",
        values: %{},
        key: true,
        danger: false
      },
      %{label: "Passed in", event: "passed_in", values: %{}, key: false, danger: false}
    ]
  end

  defp stage_actions(%{stage: :back_on_market} = board) do
    re_approaches =
      board.underbidders
      |> Enum.with_index()
      |> Enum.map(fn {underbidder, index} ->
        %{
          label: "Re-approach #{underbidder.buyer.name} at #{Board.money(underbidder.amount)}",
          event: "re_approach",
          values: %{"buyer_id" => underbidder.buyer.id},
          key: index == 0,
          danger: false,
          hint: finance_words(underbidder)
        }
      end)

    re_approaches ++
      [
        %{
          label: "Relaunch the campaign",
          event: "relaunch_campaign",
          values: %{},
          key: false,
          danger: false,
          hint: "Fresh marketing, new buyers"
        }
      ]
  end

  defp stage_actions(%{stage: :cooling} = board) do
    [
      %{
        label: "#{buyer_name(board, board.contract.buyer_id)} rescinds during cooling off",
        event: "rescind",
        values: %{"buyer_id" => board.contract.buyer_id},
        key: false,
        danger: true
      }
    ]
  end

  defp stage_actions(%{stage: :conditions} = board) do
    []
    |> maybe_condition(
      board,
      :finance,
      "Lender approves finance",
      "finance_approved",
      "Lender declines",
      "finance_declined"
    )
    |> maybe_condition(
      board,
      :inspection,
      "Building & pest report accepted",
      "inspection_satisfied",
      "Report finds a defect",
      "inspection_failed"
    )
    |> maybe_condition(
      board,
      :title,
      "Title search comes back clear",
      "title_clear",
      "Title search finds an encumbrance",
      "title_encumbered"
    )
  end

  defp stage_actions(%{stage: :awaiting_settlement} = board) do
    [
      %{label: "Settlement completes", event: "settle", values: %{}, key: true, danger: false},
      %{
        label: "#{buyer_name(board, board.contract.buyer_id)} defaults at settlement",
        event: "buyer_defaults",
        values: %{},
        key: false,
        danger: true
      }
    ]
  end

  defp stage_actions(_board), do: []

  defp maybe_condition(actions, board, kind, good_label, good_event, bad_label, bad_event) do
    case condition_by_kind(board, kind) do
      %{status: :pending} ->
        actions ++
          [
            %{
              label: good_label,
              event: good_event,
              values: %{},
              key: false,
              danger: false,
              group: Sale.ConditionKind.label(kind)
            },
            %{
              label: bad_label,
              event: bad_event,
              values: %{},
              key: false,
              danger: true,
              group: Sale.ConditionKind.label(kind)
            }
          ]

      _resolved ->
        actions
    end
  end

  defp offer_actions(board, offer) do
    name = buyer_name(board, offer.buyer_id)

    [
      %{
        label: "Accept #{name} at #{Board.money(offer.amount)}",
        event: "accept_offer",
        values: %{"offer_id" => offer.id},
        key: true,
        danger: false,
        group: name
      },
      %{
        label: "#{name} withdraws",
        event: "withdraw_offer",
        values: %{"offer_id" => offer.id},
        key: false,
        danger: true,
        group: name
      }
    ]
  end

  defp stage_action_buttons(assigns) do
    ~H"""
    <%= for action <- stage_actions(@board) do %>
      <div :if={Map.get(action, :group)} class="grp">{action.group}</div>
      <button
        class={["do", action.key && "key", action.danger && "no"]}
        phx-click={action.event}
        {phx_values(action.values)}
      >
        {action.label}
        <span :if={Map.get(action, :hint)} class="hint">{action.hint}</span>
      </button>
      <form
        :if={action.event == "accept_offer"}
        phx-submit="counter_offer"
        style="display:flex;gap:6px;margin:-2px 0 2px"
      >
        <input type="hidden" name="offer_id" value={action.values["offer_id"]} />
        <input type="number" name="amount" placeholder="Counter with $" style="flex:1" />
        <button class="do" type="submit" style="width:auto">Counter</button>
      </form>
    <% end %>
    """
  end

  defp phx_values(values) do
    for {key, value} <- values, into: %{}, do: {"phx-value-#{key}", value}
  end
end
