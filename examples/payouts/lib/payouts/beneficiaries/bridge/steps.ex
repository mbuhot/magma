defmodule Payouts.Beneficiaries.Bridge.Steps do
  @moduledoc false

  alias Payouts.Offramp
  alias Payouts.Provider

  defmodule Register do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{beneficiary: beneficiary, onboarding: onboarding}, _context, _options) do
      Provider.add_beneficiary(onboarding.account_ref, %{
        account_number: beneficiary.account_number,
        bank_code: beneficiary.bank_code
      })
    end

    @impl true
    def undo(%{provider_ref: provider_ref}, _arguments, _context, _options) do
      Provider.remove_beneficiary(provider_ref)
    end
  end

  defmodule Attach do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{beneficiary: beneficiary, registration: registration}, _context, _options) do
      Offramp.attach_beneficiary_ref(beneficiary.id, %{provider_ref: registration.provider_ref})
    end

    @impl true
    def undo(beneficiary, _arguments, _context, _options) do
      case Offramp.release_beneficiary_ref(beneficiary.id) do
        {:ok, _released} -> :ok
        error -> error
      end
    end
  end
end
