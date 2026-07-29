defmodule Payouts.Offramp.Transfer do
  @moduledoc """
  One request to move a customer's balance out to a bank account.

  The payout that carries it out runs under an id derived from this row, so the workflow, its
  checkpoints and what it is parked on are all loadable from here without anything being
  stored to point at them.
  """

  use Ash.Resource, domain: Payouts.Offramp, data_layer: AshPostgres.DataLayer

  require Ash.Query

  alias Payouts.Offramp.Calculations.Engine
  alias Payouts.Offramp.Payout

  postgres do
    table("transfers")
    repo(Payouts.Repo)
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:source_amount_cents, :integer, allow_nil?: false, public?: true)
    attribute(:destination_currency, :string, allow_nil?: false, public?: true)

    attribute(:status, Payouts.Offramp.TransferStatus,
      allow_nil?: false,
      default: :requested,
      public?: true
    )

    attribute(:provider_reference, :string, public?: true)
    timestamps()
  end

  relationships do
    belongs_to(:customer, Payouts.Offramp.Customer, allow_nil?: false, public?: true)
    has_many(:ledger_entries, Payouts.Offramp.LedgerEntry)
  end

  calculations do
    calculate(:workflow, :term, {Engine, part: :workflow})
    calculate(:tape, :term, {Engine, part: :tape})
    calculate(:waiting_on, :term, {Engine, part: :waiting_on})
    calculate(:rail, :term, {Engine, part: :rail})
    calculate(:rail_tape, :term, {Engine, part: :rail_tape})
  end

  actions do
    defaults([:read])

    read :by_id do
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    read :feed do
      description("Every transfer, newest first, with the customer and the run carrying it.")
      prepare(build(load: [:customer, :workflow], sort: [id: :desc]))
    end

    read :payout do
      description("One transfer with everything the payout page shows.")
      get?(true)
      argument(:id, :uuid_v7, allow_nil?: false)
      filter(expr(id == ^arg(:id)))

      prepare(
        build(
          load: [
            :customer,
            :workflow,
            :tape,
            :waiting_on,
            :rail,
            :rail_tape,
            ledger_entries: Ash.Query.sort(Payouts.Offramp.LedgerEntry, :id)
          ]
        )
      )
    end

    create :request do
      accept([:customer_id, :source_amount_cents, :destination_currency])
    end

    create :request_payout do
      description("Asks for a payout and starts the workflow that carries it out.")
      accept([:customer_id, :source_amount_cents, :destination_currency])

      change(Payouts.Offramp.Changes.RunPayout)
    end

    update :set_status do
      accept([:status, :provider_reference])
      require_atomic?(false)
    end

    action :approve_quote, :term do
      description("The customer approving the quote they were shown.")
      argument(:transfer_id, :uuid_v7, allow_nil?: false)
      argument(:confirmed_by, :string, allow_nil?: false, default: "console")

      run(fn input, _context ->
        signal(input, "confirm", %{confirmed_by: input.arguments.confirmed_by})
      end)
    end

    action :deliver_settlement, :term do
      description("The rail's webhook arriving, saying how the transfer went.")
      argument(:transfer_id, :uuid_v7, allow_nil?: false)

      argument(:outcome, :atom,
        allow_nil?: false,
        constraints: [one_of: [:completed, :rejected]]
      )

      run(fn input, _context ->
        signal(input, "settlement", %{outcome: input.arguments.outcome})
      end)
    end

    action :resume_payout, :term do
      description("Puts the run back on its queue, which is what recovery does after a crash.")
      argument(:transfer_id, :uuid_v7, allow_nil?: false)

      run(fn input, _context ->
        %{workflow_id: Payout.workflow_id(input.arguments.transfer_id)}
        |> Magma.Worker.new(queue: :payouts)
        |> Oban.insert()
      end)
    end

    action :cancel_payout, :term do
      description("Stops the run and takes back everything it has done.")
      argument(:transfer_id, :uuid_v7, allow_nil?: false)

      run(fn input, _context ->
        input.arguments.transfer_id |> Payout.workflow_id() |> Magma.cancel()
      end)
    end
  end

  defp signal(input, name, payload) do
    input.arguments.transfer_id
    |> Payout.workflow_id()
    |> Magma.signal(name, payload)
  end
end
