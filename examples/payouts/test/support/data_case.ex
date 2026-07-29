defmodule Payouts.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Magma.Testing, repo: Payouts.Repo

      import Payouts.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Payouts.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    owner = self()
    Payouts.Provider.open()
    on_exit(fn -> Payouts.Provider.close(owner) end)

    :ok
  end

  @doc "A customer whose balance is an opening deposit, since a balance is only ever posted."
  def a_customer(balance_cents \\ 100_000) do
    {:ok, customer} = Payouts.Offramp.open_customer("Ada", balance_cents)

    customer
  end

  @doc """
  A customer the rail will pay: taken on, and given an account where the rail wants one.

  Seeded rather than run, so a test about paying out does not pay for the two workflows that
  put the customer in that position. `beneficiary_test` and `onboarding_test` run the real ones.
  """
  def ready_for_rail(customer, currency \\ "EUR") do
    an_onboarding(customer, currency)
    if Payouts.Routing.beneficiary_for(currency), do: a_beneficiary(customer, currency)

    customer
  end

  @doc "A customer the rail has taken on, without paying for the KYC run."
  def an_onboarding(customer, currency \\ "EUR") do
    {:ok, onboarding} =
      Payouts.Offramp.begin_onboarding(%{
        customer_id: customer.id,
        destination_currency: currency
      })

    {:ok, active} =
      Payouts.Offramp.record_onboarding_progress(onboarding.id, %{
        status: :active,
        account_ref: "acc_seeded"
      })

    active
  end

  @doc "A destination the rail has already accepted, without paying for the registration run."
  def a_beneficiary(customer, currency \\ "EUR") do
    {:ok, beneficiary} =
      Payouts.Offramp.record_beneficiary(%{
        customer_id: customer.id,
        destination_currency: currency,
        account_number: "DE00BRDG0000001123456702",
        bank_code: "BRDGDEFF"
      })

    {:ok, registered} =
      Payouts.Offramp.attach_beneficiary_ref(beneficiary.id, %{provider_ref: "ben_seeded"})

    registered
  end

  def a_transfer(customer, amount_cents \\ 25_000) do
    {:ok, transfer} =
      Payouts.Offramp.request_payout(%{
        customer_id: customer.id,
        source_amount_cents: amount_cents,
        destination_currency: "EUR"
      })

    transfer
  end
end
