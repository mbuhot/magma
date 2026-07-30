defmodule Agency.Sale.Attempt.Steps do
  @moduledoc "The steps one generation of the attempt to sell is made of."

  alias Agency.Sale.Jurisdiction
  alias Agency.Sale.Window

  @doc "How long the buyer's right to rescind runs, in the jurisdiction governing the contract."
  @spec cooling_off_window(map(), map()) :: pos_integer()
  def cooling_off_window(%{governing_window: jurisdiction}, _context) do
    Window.cooling_off(Jurisdiction.cooling_off(jurisdiction).business_days)
  end

  defmodule Setting do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale
    alias Agency.Sale.Window

    @impl true
    def run(%{sale_attempt_id: sale_attempt_id}, _context, _options) do
      attempt = Sale.get_attempt!(sale_attempt_id, load: [agency_agreement: [:property]])
      agreement = attempt.agency_agreement

      {:ok,
       %{
         sale_attempt_id: attempt.id,
         agency_agreement_id: agreement.id,
         generation: attempt.generation,
         sale_method: attempt.sale_method,
         jurisdiction: agreement.property.jurisdiction,
         vendor_name: agreement.vendor_name,
         commission_rate: agreement.commission_rate,
         commission_trigger: agreement.commission_trigger,
         guide_price: agreement.guide_price,
         trust_account: "#{agreement.agent_name} Trust",
         offer_deadline: Window.offer_close()
       }}
    end
  end

  defmodule LeadingOffer do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{sale_attempt_id: sale_attempt_id}, _context, _options) do
      {:ok, sale_attempt_id |> Sale.live_offers_for_attempt!() |> List.first()}
    end
  end

  defmodule NegotiatedSale do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{terms: terms, setting: setting}, _context, _options) do
      {:ok, %{terms: terms, governing_window: setting.jurisdiction}}
    end
  end

  defmodule AuctionSale do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale.Jurisdiction

    @impl true
    def run(%{terms: terms, setting: setting}, context, _options) do
      {:ok, %{terms: terms, governing_window: governing_window(setting, verdict(context))}}
    end

    defp governing_window(setting, :sold) do
      if Jurisdiction.cooling_off(setting.jurisdiction).auction == :exempt do
        :exempt
      else
        setting.jurisdiction
      end
    end

    defp governing_window(setting, _passed_in), do: setting.jurisdiction

    defp verdict(context) do
      context.magma.workflow_id
      |> Magma.child_id(:auction)
      |> Magma.steps()
      |> Enum.find_value(:passed_in, fn checkpoint ->
        if checkpoint.step_label == inspect(:verdict), do: checkpoint.output
      end)
    end
  end

  defmodule Exchange do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale
    alias Agency.Sale.Clock
    alias Agency.Sale.Money
    alias Agency.Sale.Window

    @condition_business_days [finance: 14, inspection: 7, title: 21]

    @impl true
    def run(%{setting: setting, sale: sale}, _context, _options) do
      terms = sale.terms
      exchanged_at = DateTime.utc_now() |> DateTime.truncate(:second)
      exchange_date = DateTime.to_date(exchanged_at)

      contract =
        Sale.exchange_contract!(%{
          sale_attempt_id: setting.sale_attempt_id,
          buyer_id: terms.buyer_id,
          price: terms.price,
          exchanged_at: exchanged_at,
          settlement_date: Window.settlement_date(exchange_date)
        })

      deposit =
        Sale.collect_deposit!(%{
          contract_id: contract.id,
          amount: div(terms.price, 10),
          held_in: setting.trust_account
        })

      commission =
        Sale.accrue_commission!(%{
          sale_attempt_id: setting.sale_attempt_id,
          amount: Money.commission(terms.price, setting.commission_rate),
          accrued_at: exchanged_at,
          payable_on: setting.commission_trigger
        })

      impose_conditions(contract, exchange_date, setting.jurisdiction)

      Sale.set_buyer_register_status!(terms.buyer_id, %{register_status: :under_contract})

      {:ok,
       %{
         contract_id: contract.id,
         deposit_id: deposit.id,
         deposit_amount: deposit.amount,
         commission_id: commission.id,
         commission_amount: commission.amount,
         buyer_id: terms.buyer_id,
         price: terms.price,
         exchanged_at: exchanged_at,
         settlement_date: contract.settlement_date
       }}
    end

    defp impose_conditions(contract, exchange_date, jurisdiction) do
      Enum.each(@condition_business_days, fn {kind, business_days} ->
        {due_date, _holidays} =
          Clock.add_business_days(exchange_date, business_days, jurisdiction)

        Sale.impose_condition!(%{contract_id: contract.id, kind: kind, due_date: due_date})
      end)
    end
  end

  defmodule NoCoolingOff do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, :none}
  end

  defmodule ContractHolds do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, :held}
  end

  defmodule Rescind do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale
    alias Agency.Sale.Jurisdiction
    alias Agency.Sale.Money

    @impl true
    def run(%{setting: setting, exchange: exchange}, _context, _options) do
      forfeit_rate = Jurisdiction.cooling_off(setting.jurisdiction).forfeit_rate
      forfeited = Money.forfeit(exchange.price, forfeit_rate)

      Sale.settle_deposit_status!(exchange.deposit_id, %{
        status: :forfeited,
        forfeited_to: setting.vendor_name
      })

      Sale.write_back_commission!(exchange.commission_id, %{})

      Sale.close_attempt!(setting.sale_attempt_id, %{
        outcome: :rescinded,
        closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      Sale.set_buyer_register_status!(exchange.buyer_id, %{register_status: :rescinded})

      {:ok,
       %{
         forfeited: forfeited,
         refunded: exchange.deposit_amount - forfeited,
         forfeited_to: setting.vendor_name
       }}
    end
  end

  defmodule Rescinded do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, :rescinded}
  end

  defmodule ConditionFailure do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{setting: setting, exchange: exchange}, _context, _options) do
      Sale.settle_deposit_status!(exchange.deposit_id, %{status: :refunded})
      Sale.write_back_commission!(exchange.commission_id, %{})

      Sale.close_attempt!(setting.sale_attempt_id, %{
        outcome: :condition_failed,
        closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      Sale.set_buyer_register_status!(exchange.buyer_id, %{register_status: :missed})

      {:ok, %{refunded: exchange.deposit_amount}}
    end
  end

  defmodule AdvanceCommission do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{setting: setting, exchange: exchange}, _context, _options) do
      commission =
        Sale.disburse_commission!(exchange.commission_id, %{
          disbursed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          paid_from: setting.trust_account
        })

      {:ok, %{disbursed_at: commission.disbursed_at, paid_from: commission.paid_from}}
    end
  end

  defmodule Settle do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{setting: setting, exchange: exchange}, _context, _options) do
      settled_at = DateTime.utc_now() |> DateTime.truncate(:second)

      Sale.settle_deposit_status!(exchange.deposit_id, %{status: :released})
      disburse(setting, exchange, settled_at)
      Sale.close_attempt!(setting.sale_attempt_id, %{outcome: :settled, closed_at: settled_at})

      {:ok, %{settled_at: settled_at, contract_id: exchange.contract_id}}
    end

    defp disburse(%{commission_trigger: :on_unconditional}, _exchange, _settled_at), do: :ok

    defp disburse(setting, exchange, settled_at) do
      Sale.disburse_commission!(exchange.commission_id, %{
        disbursed_at: settled_at,
        paid_from: setting.trust_account
      })

      :ok
    end
  end

  defmodule BuyerDefault do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{setting: setting, exchange: exchange}, _context, _options) do
      defaulted_at = DateTime.utc_now() |> DateTime.truncate(:second)

      Sale.settle_deposit_status!(exchange.deposit_id, %{
        status: :forfeited,
        forfeited_to: setting.vendor_name
      })

      disburse(setting, exchange, defaulted_at)

      Sale.close_attempt!(setting.sale_attempt_id, %{
        outcome: :buyer_default,
        closed_at: defaulted_at
      })

      Sale.set_buyer_register_status!(exchange.buyer_id, %{register_status: :defaulted})

      {:ok,
       %{
         forfeited: exchange.deposit_amount,
         to_vendor: exchange.deposit_amount - exchange.commission_amount
       }}
    end

    defp disburse(%{commission_trigger: :on_unconditional}, _exchange, _defaulted_at), do: :ok

    defp disburse(_setting, exchange, defaulted_at) do
      Sale.disburse_commission!(exchange.commission_id, %{
        disbursed_at: defaulted_at,
        paid_from: "forfeited deposit"
      })

      :ok
    end
  end

  defmodule CloseWithoutOffers do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale

    @impl true
    def run(%{setting: setting}, _context, _options) do
      Sale.close_attempt!(setting.sale_attempt_id, %{
        outcome: :no_offers,
        closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      {:ok, %{outcome: :no_sale, reason: :no_offers}}
    end
  end

  defmodule Failed do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, options) do
      {:ok, %{outcome: :failed, reason: Keyword.fetch!(options, :reason)}}
    end
  end

  defmodule Settled do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{settlement: settlement}, _context, _options) do
      {:ok, %{outcome: :settled, contract_id: settlement.contract_id}}
    end
  end

  defmodule Reported do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{result: result}, _context, _options), do: {:ok, result}
  end

  defmodule RegisterExhausted do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options) do
      {:ok, %{outcome: :no_sale, reason: :register_exhausted}}
    end
  end

  defmodule Succession do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale.Register

    @impl true
    def run(%{attempt: %{outcome: :settled}}, _context, _options), do: {:ok, :report}

    def run(%{setting: setting}, _context, _options) do
      case Register.approachable(setting.agency_agreement_id, setting.sale_attempt_id) do
        [] -> {:ok, :register_exhausted}
        [_first | _rest] -> {:ok, :next_generation}
      end
    end
  end

  defmodule OpenSuccessor do
    @moduledoc false
    use Reactor.Step

    alias Agency.Sale
    alias Agency.Sale.Register
    alias Agency.Sale.Window

    @impl true
    def run(%{setting: setting}, _context, _options) do
      successor =
        Sale.open_attempt!(%{
          agency_agreement_id: setting.agency_agreement_id,
          predecessor_id: setting.sale_attempt_id,
          generation: setting.generation + 1,
          sale_method: :treaty,
          opened_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      setting.agency_agreement_id
      |> Register.approachable(setting.sale_attempt_id)
      |> Enum.each(fn {buyer, offer} ->
        Sale.make_offer!(%{
          sale_attempt_id: successor.id,
          buyer_id: buyer.id,
          amount: offer.amount,
          requested_conditions: offer.requested_conditions,
          expires_at: Window.offer_expiry(),
          supersedes_id: offer.id
        })
      end)

      {:ok, %{sale_attempt_id: successor.id, generation: successor.generation}}
    end
  end
end
