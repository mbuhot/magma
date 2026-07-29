defmodule Payouts.OnboardingTest do
  use Payouts.DataCase, async: true

  alias Payouts.Offramp
  alias Payouts.Provider

  defp onboard(customer, currency) do
    {:ok, onboarding} = Offramp.onboard(customer.id, currency)
    run_workflows(queue: :onboarding)

    {onboarding, Offramp.Onboarding.workflow_id(onboarding.id)}
  end

  defp reload(onboarding) do
    {:ok, reloaded} = Offramp.get_onboarding(onboarding.id)
    reloaded
  end

  test "the rail that onboards a customer is the one config says serves the currency" do
    customer = a_customer()

    {_onboarding, bridge} = onboard(customer, "EUR")
    {_other, meridian} = onboard(a_customer(), "USD")

    assert status(bridge) == :completed
    assert status(meridian) == :completed
    assert length(tape(bridge)) > length(tape(meridian))
  end

  test "asking to onboard the same customer twice runs one KYC" do
    customer = a_customer()

    onboard(customer, "EUR")
    onboard(customer, "EUR")

    assert Provider.calls(:create_account) == 1
  end

  test "Bridge asks for a submission and every document it wants" do
    customer = a_customer()

    {onboarding, workflow} = onboard(customer, "EUR")

    assert reload(onboarding).status == :active
    assert Provider.calls(:open_submission) == 1
    assert Provider.calls(:submit_questionnaire) == 1

    for kind <- Provider.required_documents() do
      assert Provider.calls({:upload_document, kind}) == 1
    end

    assert Provider.calls(:close_submission) == 1
    assert ":decision" in tape(workflow)
  end

  test "Meridian asks for neither, and issues the account instead" do
    customer = a_customer()

    {onboarding, workflow} = onboard(customer, "USD")

    assert reload(onboarding).status == :active
    assert reload(onboarding).identity_ref =~ "US00MERI"
    assert Provider.calls(:open_submission) == 0
    assert Provider.calls(:issue_identity) == 1
    assert tape(workflow) == [":onboarding", ":account", ":identity"]
  end

  test "each document Bridge wants is uploaded exactly once, even when the run comes back" do
    customer = a_customer()

    {_onboarding, workflow} = onboard(customer, "EUR")

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow}})

    for kind <- Provider.required_documents() do
      assert Provider.calls({:upload_document, kind}) == 1
    end

    assert Provider.calls(:create_account) == 1
  end

  test "a rejected submission is resumed into rather than started over" do
    customer = a_customer()
    Provider.fail_next(:close_submission)

    {onboarding, workflow} = onboard(customer, "EUR")

    assert reload(onboarding).status == :resubmission_required

    Magma.Worker.perform(%Oban.Job{args: %{"workflow_id" => workflow}})

    assert Provider.calls(:create_account) == 1
    assert Provider.calls(:open_submission) == 1
    assert Provider.calls({:upload_document, :passport}) == 1
  end

  test "onboarding is never undone, so a customer keeps the documents they sent" do
    customer = a_customer()

    {_onboarding, workflow} = onboard(customer, "EUR")

    {:ok, _cancelling} = Magma.cancel(workflow)
    for queue <- [:onboarding, :default, :payouts], do: run_workflows(queue: queue)

    assert status(workflow) == :cancelled
    assert Provider.calls(:create_account) == 1
    assert ":account" in tape(workflow)
    assert ":decision" in tape(workflow)
  end
end
