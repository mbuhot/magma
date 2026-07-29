defmodule Payouts.Provider do
  @moduledoc """
  The bank rail, stood in for.

  Every call records what it did and can be told to fail, so a test can prove that a run
  recovering from a crash does not price twice or send twice.

  A provider belongs to the process that opened one, found through `$callers` the way Ecto's
  sandbox finds a connection's owner. That is what lets tests assert on call counts while
  running at the same time as each other. A process that opened none gets the shared provider,
  which is the only one a running system has.
  """

  use Agent

  @shared :shared

  def start_link(_options \\ []) do
    Agent.start_link(fn -> %{@shared => fresh()} end, name: __MODULE__)
  end

  @doc "Gives the calling process a provider of its own."
  def open do
    pid = self()
    Agent.update(__MODULE__, &Map.put(&1, pid, fresh()))
  end

  @doc "Takes back a provider, named by the process that opened it."
  def close(pid \\ self()), do: Agent.update(__MODULE__, &Map.delete(&1, pid))

  @doc "How many times a call has been made."
  def calls(name), do: get(&Enum.count(&1.calls, fn call -> call == name end))

  @doc "Every call the provider has taken, newest first."
  def tape, do: get(& &1.calls)

  @doc "The calls that are armed to fail the next time they are made."
  def armed, do: get(fn state -> for {name, true} <- state.fail, do: name end)

  def fail_next(name), do: update(&put_in(&1.fail[name], true))

  @doc "Prices a payout. The rate moves on every call, so a replayed quote is visible."
  def quote_payout(amount_cents) do
    record(:quote_payout)

    rate = get_and_update(&{&1.rate, %{&1 | rate: &1.rate + 1}})

    %{rate: rate, destination_amount: div(amount_cents * rate, 100), quoted_at: rate}
  end

  @doc "Hands the transfer to the rail."
  def send_payout(transfer_id, destination_amount, beneficiary_ref \\ nil) do
    record(:send_payout)

    if taking?(:send_payout) do
      {:error, :provider_unavailable}
    else
      {:ok,
       %{
         reference: "prv_" <> String.slice(transfer_id, 0, 8),
         amount: destination_amount,
         beneficiary_ref: beneficiary_ref
       }}
    end
  end

  @doc """
  Which documents Bridge asks a customer for.

  Sorted, because a `map` over it names its generated steps by index and a source that
  reorders would replay the wrong checkpoint into an element.
  """
  def required_documents, do: Enum.sort([:passport, :proof_of_address, :source_of_funds])

  @doc "Opens an account with a provider."
  def create_account(customer_id) do
    record(:create_account)
    %{account_ref: "acc_" <> String.slice(customer_id, 0, 8)}
  end

  @doc "Records that the customer accepted the provider's terms."
  def accept_terms(account) do
    record(:accept_terms)
    %{accepted: account.account_ref}
  end

  @doc "Opens a KYC submission to hang documents off."
  def open_submission(account) do
    record(:open_submission)
    %{submission_ref: "sub_" <> account.account_ref}
  end

  @doc "Sends the customer's profile to the open submission."
  def submit_profile(submission, name) do
    record(:submit_profile)
    %{submission_ref: submission.submission_ref, name: name}
  end

  @doc "Answers the provider's questionnaire."
  def submit_questionnaire(submission) do
    record(:submit_questionnaire)
    %{submission_ref: submission.submission_ref, answered: true}
  end

  @doc "Uploads one document against the open submission."
  def upload_document(submission, kind) do
    record({:upload_document, kind})
    %{submission_ref: submission.submission_ref, kind: kind}
  end

  @doc "Closes the submission and returns the decision."
  def close_submission(submission) do
    record(:close_submission)

    if taking?(:close_submission) do
      {:error, :resubmission_required}
    else
      {:ok, %{submission_ref: submission.submission_ref, status: :active}}
    end
  end

  @doc "Issues the account identifier the customer is paid into."
  def issue_identity(account) do
    record(:issue_identity)
    %{iban: "US00MERI" <> String.slice(account.account_ref, 0, 8)}
  end

  @doc "Tells the rail about a bank account it is to pay, under an onboarded account."
  def add_beneficiary(account_ref, destination) do
    record(:add_beneficiary)

    if taking?(:add_beneficiary) do
      {:error, :beneficiary_refused}
    else
      {:ok, %{provider_ref: "ben_" <> destination.account_number, account_ref: account_ref}}
    end
  end

  @doc "Withdraws a recipient, so a registration that did not finish leaves nothing to pay."
  def remove_beneficiary(provider_ref) do
    record({:remove_beneficiary, provider_ref})
    :ok
  end

  @doc "Moves funds into the vault a rail pays out of."
  def fund_vault(amount) do
    record(:fund_vault)
    %{funded: amount}
  end

  defp record(name), do: update(&%{&1 | calls: [name | &1.calls]})

  defp taking?(name) do
    get_and_update(fn state ->
      {Map.get(state.fail, name, false), put_in(state.fail[name], false)}
    end)
  end

  defp fresh, do: %{calls: [], fail: %{}, rate: 278}

  defp get(fun) do
    owner = owner()

    Agent.get(__MODULE__, &fun.(Map.fetch!(&1, owner)))
  end

  defp update(fun) do
    owner = owner()

    Agent.update(__MODULE__, &Map.update!(&1, owner, fun))
  end

  defp get_and_update(fun) do
    owner = owner()

    Agent.get_and_update(__MODULE__, fn state ->
      {answer, updated} = fun.(Map.fetch!(state, owner))

      {answer, Map.put(state, owner, updated)}
    end)
  end

  # Resolved in the calling process, since a function handed to an agent runs inside the agent,
  # where `self()` and `$callers` are the agent's own.
  defp owner do
    opened = Agent.get(__MODULE__, &Map.keys/1)

    Enum.find([self() | Process.get(:"$callers", [])], @shared, &(&1 in opened))
  end
end
