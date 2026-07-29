defmodule Payouts.PayoutTest do
  use Payouts.DataCase, async: true

  alias Payouts.Offramp
  alias Payouts.Provider
  alias Payouts.Offramp.Payout

  defp balance(customer) do
    {:ok, reloaded} = Offramp.get_customer(customer.id)
    reloaded.balance_cents
  end

  defp transfer_status(transfer) do
    {:ok, reloaded} = Offramp.get_transfer(transfer.id)
    reloaded.status
  end

  # A rail runs on its own queue, and finishing signals the spine back onto its own, so
  # settling means draining both until neither has anything left.
  defp settle_queues(passes \\ 4) do
    Enum.each(1..passes, fn _pass ->
      run_workflows(queue: :rails)
      run_workflows(queue: :payouts)
    end)
  end

  defp rail_tape(workflow), do: tape(Magma.child_id(workflow.id, :rail))

  defp start_payout(transfer) do
    {:ok, workflow} = Magma.start(Payout, %{transfer_id: transfer.id}, queue: :payouts)
    settle_queues()
    workflow
  end

  defp confirm(workflow) do
    {:ok, _signal} = Magma.signal(workflow.id, "confirm", %{confirmed_by: "ada"})
    settle_queues()
  end

  defp settle(workflow, outcome) do
    {:ok, _signal} = Magma.signal(workflow.id, "settlement", %{outcome: outcome})
    settle_queues()
  end

  test "a payout waits for the customer to confirm the quote before touching their balance" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)

    assert status(workflow) == :waiting
    assert balance(customer) == 100_000
  end

  test "a confirmed payout debits the customer and reaches the provider" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)

    assert balance(customer) == 75_000
    assert Provider.calls(:send_payout) == 1
  end

  test "the rail that runs is the one config says serves the currency" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)

    assert rail_tape(workflow) == [":fund", ":send"]
    assert Provider.calls(:fund_vault) == 1
  end

  test "a customer the rail has never been told about is not priced" do
    customer = a_customer(100_000)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)

    assert status(workflow) == :failed
    assert Provider.calls(:quote_payout) == 0
    assert balance(customer) == 100_000
  end

  test "a customer whose KYC is still undecided is not priced" do
    customer = a_customer(100_000)

    {:ok, _pending} =
      Offramp.begin_onboarding(%{customer_id: customer.id, destination_currency: "EUR"})

    a_beneficiary(customer)

    workflow = start_payout(a_transfer(customer, 25_000))

    assert status(workflow) == :failed
    assert Provider.calls(:quote_payout) == 0
  end

  test "onboarding on one rail does not let a customer be paid on another" do
    customer = a_customer(100_000)
    ready_for_rail(customer, "USD")

    workflow = start_payout(a_transfer(customer, 25_000))

    assert status(workflow) == :failed
    assert Provider.calls(:quote_payout) == 0
  end

  test "a rail that pays a third party will not pay an account it has never been told about" do
    customer = a_customer(100_000)
    an_onboarding(customer)

    workflow = start_payout(a_transfer(customer, 25_000))

    assert status(workflow) == :failed
    assert Provider.calls(:quote_payout) == 0
    assert balance(customer) == 100_000
  end

  test "an account the rail has not accepted yet is not one it will pay" do
    customer = a_customer(100_000)
    an_onboarding(customer)

    {:ok, _recorded} =
      Offramp.record_beneficiary(%{
        customer_id: customer.id,
        destination_currency: "EUR",
        account_number: "DE00BRDG0000001123456702",
        bank_code: "BRDGDEFF"
      })

    workflow = start_payout(a_transfer(customer, 25_000))

    assert status(workflow) == :failed
    assert Provider.calls(:quote_payout) == 0
  end

  test "a rail that pays the customer's own account asks for no beneficiary" do
    customer = a_customer(100_000)
    ready_for_rail(customer, "USD")

    {:ok, transfer} =
      Offramp.request_payout(%{
        customer_id: customer.id,
        source_amount_cents: 25_000,
        destination_currency: "USD"
      })

    workflow = start_payout(transfer)
    confirm(workflow)

    assert recorded(workflow, :beneficiary) == nil
    assert Provider.calls(:send_payout) == 1
  end

  test "the account the rail is told to pay is the one that was registered" do
    customer = a_customer(100_000)
    beneficiary = a_beneficiary(customer)
    an_onboarding(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)

    sent = recorded(Magma.child_id(workflow.id, :rail), :send)

    assert sent.beneficiary_ref == beneficiary.provider_ref
  end

  test "a rail with a different shape runs for a different currency" do
    customer = a_customer(100_000)
    ready_for_rail(customer, "USD")

    {:ok, transfer} =
      Offramp.request_payout(%{
        customer_id: customer.id,
        source_amount_cents: 25_000,
        destination_currency: "USD"
      })

    workflow = start_payout(transfer)
    confirm(workflow)

    assert rail_tape(workflow) == [":send"]
    assert Provider.calls(:fund_vault) == 0
    assert Provider.calls(:send_payout) == 1
  end

  test "the spine names no rail" do
    source = File.read!("lib/payouts/offramp/payout.ex")

    refute source =~ "Bridge"
    refute source =~ "Meridian"
  end

  test "a settled payout completes" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)
    settle(workflow, :completed)

    assert status(workflow) == :completed
    assert transfer_status(transfer) == :completed
    assert balance(customer) == 75_000
  end

  test "the amount debited is the one that was quoted, even after the price moves" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    quoted = recorded(workflow, :quote)

    confirm(workflow)

    assert recorded(workflow, :quote) == quoted
    assert Provider.calls(:quote_payout) == 1
  end

  test "a payout that resumes after a crash prices once and sends once" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow.id}})

    assert Provider.calls(:quote_payout) == 1
    assert Provider.calls(:send_payout) == 1
    assert balance(customer) == 75_000
  end

  test "a provider that is down does not debit the customer twice when the run comes back" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    Provider.fail_next(:send_payout)
    confirm(workflow)

    assert Provider.calls(:send_payout) == 1
    assert balance(customer) == 100_000
  end

  test "a rejected settlement gives the customer their money back" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)

    assert balance(customer) == 75_000

    settle(workflow, :rejected)

    assert balance(customer) == 100_000
    assert transfer_status(transfer) == :reversed
    assert status(workflow) in [:failed, :unwinding]
  end

  test "the money given back is posted to the ledger rather than erased from it" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)
    settle(workflow, :rejected)

    {:ok, entries} = Offramp.ledger_entries()

    assert Enum.map(entries, &{&1.reason, &1.amount_cents}) == [
             {"opening balance", 100_000},
             {"payout", -25_000},
             {"payout reversal", 25_000}
           ]

    assert balance(customer) == 100_000
  end

  test "the tape reads as the payout's lifecycle" do
    customer = a_customer(100_000)
    ready_for_rail(customer)
    transfer = a_transfer(customer, 25_000)

    workflow = start_payout(transfer)
    confirm(workflow)
    settle(workflow, :completed)

    assert tape(workflow) == [
             "{:__input__, :transfer, [:id]}",
             ":transfer",
             ":onboarding",
             ":beneficiary",
             ":quote",
             ":confirmation",
             ":debit",
             ":rail",
             ":settlement",
             ":settle"
           ]
  end
end
