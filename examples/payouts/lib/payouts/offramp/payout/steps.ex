defmodule Payouts.Offramp.Payout.Steps do
  @moduledoc "The steps a payout is made of, each one a thing that happens to the outside world."

  alias Payouts.Offramp
  alias Payouts.Provider

  defmodule Quote do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{transfer: transfer}, _context, _options) do
      {:ok, Provider.quote_payout(transfer.source_amount_cents)}
    end
  end

  defmodule Onboarding do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{transfer: transfer}, _context, _options) do
      case Offramp.onboarding_for_rail(transfer.customer_id, transfer.destination_currency) do
        {:ok, %{status: :active} = onboarding} -> {:ok, onboarding}
        {:ok, standing} -> {:error, refused(transfer, standing)}
        _otherwise -> {:error, refused(transfer, nil)}
      end
    end

    defp refused(transfer, standing) do
      %Payouts.Offramp.NotOnboarded{
        customer_id: transfer.customer_id,
        destination_currency: transfer.destination_currency,
        status: standing && standing.status
      }
    end
  end

  defmodule Beneficiary do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{transfer: transfer}, _context, _options) do
      case Payouts.Routing.beneficiary_for(transfer.destination_currency) do
        nil -> {:ok, nil}
        _workflow -> registered(transfer)
      end
    end

    defp registered(transfer) do
      case Offramp.beneficiary_for_rail(transfer.customer_id, transfer.destination_currency) do
        {:ok, %{status: :registered} = beneficiary} ->
          {:ok, beneficiary}

        _otherwise ->
          {:error,
           %Payouts.Offramp.Unregistered{
             customer_id: transfer.customer_id,
             destination_currency: transfer.destination_currency
           }}
      end
    end
  end

  defmodule Debit do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{transfer: transfer}, _context, _options) do
      with {:ok, entry} <- post(transfer, -transfer.source_amount_cents, "payout"),
           {:ok, _transfer} <- set_status(transfer, :debited) do
        {:ok, entry}
      end
    end

    # The ledger is append-only, so taking a debit back means posting its opposite. The amount
    # comes from the entry this step recorded rather than from the transfer, so the reversal is
    # for what was actually posted. The status moves forward to `:reversed` for the same reason
    # the entry is posted rather than deleted: the debit happened, and saying otherwise would
    # disagree with the journal.
    @impl true
    def undo(entry, %{transfer: transfer}, _context, _options) do
      with {:ok, _reversal} <- post(transfer, -entry.amount_cents, "payout reversal"),
           {:ok, _transfer} <- set_status(transfer, :reversed) do
        :ok
      end
    end

    defp post(transfer, amount_cents, reason) do
      Offramp.post_ledger_entry(%{
        customer_id: transfer.customer_id,
        transfer_id: transfer.id,
        amount_cents: amount_cents,
        reason: reason
      })
    end

    defp set_status(transfer, status) do
      Offramp.set_transfer_status(transfer.id, %{status: status})
    end
  end

  defmodule Settle do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{transfer: transfer, settlement: settlement}, _context, _options) do
      case settlement do
        %{outcome: :completed} -> finish(transfer, :completed)
        %{outcome: :rejected} -> {:error, %Payouts.Offramp.Rejected{transfer_id: transfer.id}}
      end
    end

    defp finish(transfer, status) do
      Offramp.set_transfer_status(transfer.id, %{status: status})
    end
  end
end
