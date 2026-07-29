defmodule Payouts.Onboarding.Meridian.Steps do
  @moduledoc false

  alias Payouts.Provider

  defmodule CreateAccount do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{onboarding: onboarding}, _context, _options) do
      {:ok, Provider.create_account(onboarding.customer_id)}
    end
  end

  defmodule IssueIdentity do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{account: account, onboarding: onboarding}, _context, _options) do
      identity = Provider.issue_identity(account)

      Payouts.Offramp.record_onboarding_progress(onboarding.id, %{
        status: :active,
        account_ref: account.account_ref,
        identity_ref: identity.iban
      })
    end
  end
end
