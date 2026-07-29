defmodule Payouts.Onboarding.Bridge.Steps do
  @moduledoc false

  alias Payouts.Offramp
  alias Payouts.Provider

  defmodule Load do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{onboarding_id: id}, _context, _options) do
      Ash.get(Offramp.Onboarding, id, load: [:customer])
    end
  end

  defmodule CreateAccount do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{onboarding: onboarding}, _context, _options) do
      {:ok, Provider.create_account(onboarding.customer_id)}
    end
  end

  defmodule AcceptTerms do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{account: account}, _context, _options), do: {:ok, Provider.accept_terms(account)}
  end

  defmodule OpenSubmission do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{account: account}, _context, _options),
      do: {:ok, Provider.open_submission(account)}
  end

  defmodule SubmitProfile do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{submission: submission, onboarding: onboarding}, _context, _options) do
      {:ok, Provider.submit_profile(submission, onboarding.customer.name)}
    end
  end

  defmodule SubmitQuestionnaire do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{submission: submission}, _context, _options),
      do: {:ok, Provider.submit_questionnaire(submission)}
  end

  defmodule RequiredDocuments do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, Provider.required_documents()}
  end

  defmodule UploadDocument do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{kind: kind, submission: submission}, _context, _options),
      do: {:ok, Provider.upload_document(submission, kind)}
  end

  defmodule CloseSubmission do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{submission: submission, onboarding: onboarding, account: account}, _c, _o) do
      case Provider.close_submission(submission) do
        {:ok, closed} -> record(onboarding, account, closed.status)
        {:error, reason} -> record(onboarding, account, reason)
      end
    end

    defp record(onboarding, account, status) do
      Payouts.Offramp.record_onboarding_progress(onboarding.id, %{
        status: status,
        account_ref: account.account_ref
      })
    end
  end
end
