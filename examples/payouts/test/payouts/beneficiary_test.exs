defmodule Payouts.BeneficiaryTest do
  use Payouts.DataCase, async: true

  alias Payouts.Offramp
  alias Payouts.Provider
  alias Payouts.Routing

  defp onboarded(customer, currency) do
    {:ok, onboarding} = Offramp.onboard(customer.id, currency)
    run_workflows(queue: :onboarding)

    onboarding
  end

  defp recorded_account(customer, currency) do
    {:ok, beneficiary} =
      Offramp.record_beneficiary(%{
        customer_id: customer.id,
        destination_currency: currency,
        account_number: "DE00BRDG0000001123456702",
        bank_code: "BRDGDEFF"
      })

    beneficiary
  end

  defp register(beneficiary) do
    {:ok, registered} =
      Offramp.register_beneficiary(%{
        customer_id: beneficiary.customer_id,
        destination_currency: beneficiary.destination_currency,
        account_number: beneficiary.account_number,
        bank_code: beneficiary.bank_code
      })

    run_workflows(queue: :onboarding)

    Offramp.Beneficiary.workflow_id(registered.id)
  end

  defp reload(beneficiary) do
    {:ok, reloaded} = Offramp.get_beneficiary(beneficiary.id)
    reloaded
  end

  test "registering an account tells the rail about it and stores what the rail called it" do
    customer = a_customer()
    onboarded(customer, "EUR")

    beneficiary = customer |> recorded_account("EUR") |> register()

    assert status(beneficiary) == :completed
    assert Provider.calls(:add_beneficiary) == 1
  end

  test "an account the rail has accepted is one a payout may be paid to" do
    customer = a_customer()
    onboarded(customer, "EUR")

    recorded = recorded_account(customer, "EUR")
    register(recorded)

    assert reload(recorded).status == :registered
    assert reload(recorded).provider_ref == "ben_DE00BRDG0000001123456702"
  end

  test "registering the same account twice opens one recipient with the rail" do
    customer = a_customer()
    onboarded(customer, "EUR")

    recorded = recorded_account(customer, "EUR")
    workflow = register(recorded)

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow}})

    assert Provider.calls(:add_beneficiary) == 1
  end

  test "asking to register the same account twice runs one registration" do
    customer = a_customer()
    onboarded(customer, "EUR")

    recorded = recorded_account(customer, "EUR")
    register(recorded)
    register(recorded)

    assert Provider.calls(:add_beneficiary) == 1
  end

  test "an account cannot be registered before the customer is onboarded with that rail" do
    customer = a_customer()

    workflow = customer |> recorded_account("EUR") |> register()

    assert status(workflow) == :failed
    assert Provider.calls(:add_beneficiary) == 0
  end

  test "a registration that is abandoned withdraws the recipient it opened" do
    customer = a_customer()
    onboarded(customer, "EUR")

    recorded = recorded_account(customer, "EUR")
    workflow = register(recorded)

    {:ok, _cancelling} = Magma.cancel(workflow)
    run_workflows(queue: :onboarding)

    assert status(workflow) == :cancelled
    assert Provider.calls({:remove_beneficiary, "ben_DE00BRDG0000001123456702"}) == 1
    assert reload(recorded).status == :recorded
    assert reload(recorded).provider_ref == nil
  end

  test "the rail that pays the customer's own account has no registration to run" do
    assert Routing.beneficiary_for("USD") == nil
  end
end
