defmodule Agency.Sale.Attempt do
  @moduledoc """
  One generation of the attempt to sell: method, exchange, cooling off, conditions, settlement.

  The method chosen decides which child runs the sale, and everything after exchange is common
  to all three. A contract that dies at any point closes the generation and hands the register
  to a successor, so the chain runs until the property sells or nobody is left to approach.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Agency.Sale.Attempt.Steps
  alias Agency.Sale.Outcome
  alias Agency.Sale.Window

  magma do
    queue(:sales)
  end

  input(:sale_attempt_id)

  step :setting, Steps.Setting do
    argument(:sale_attempt_id, input(:sale_attempt_id))
  end

  switch :sale do
    on(result(:setting, [:sale_method]))

    matches? &(&1 == :auction) do
      dispatch :auction do
        workflow(Agency.Sale.Auction)
        queue(:sales)
        argument(:sale_attempt_id, input(:sale_attempt_id))
        argument(:reserve, result(:setting, [:guide_price]))
      end

      step :sale, Steps.AuctionSale do
        argument(:terms, result(:auction))
        argument(:setting, result(:setting))
      end
    end

    matches? &(&1 == :set_date) do
      dispatch :set_date do
        workflow(Agency.Sale.SetDateSale)
        queue(:sales)
        argument(:sale_attempt_id, input(:sale_attempt_id))
        argument(:offer_deadline, result(:setting, [:offer_deadline]))
      end

      step :sale, Steps.NegotiatedSale do
        argument(:terms, result(:set_date))
        argument(:setting, result(:setting))
      end
    end

    default do
      step :leading_offer, Steps.LeadingOffer do
        argument(:sale_attempt_id, input(:sale_attempt_id))
      end

      switch :treaty_terms do
        on(result(:leading_offer))

        matches? &is_nil(&1) do
          step(:treaty_terms, {Outcome.NoSale, reason: :lapsed})
        end

        default do
          dispatch :treaty do
            workflow(Agency.Sale.PrivateTreaty)
            queue(:sales)
            argument(:offer_id, result(:leading_offer, [:id]))
          end

          step :treaty_terms, Outcome.Reported do
            argument(:outcome, result(:treaty))
          end
        end
      end

      step :sale, Steps.NegotiatedSale do
        argument(:terms, result(:treaty_terms))
        argument(:setting, result(:setting))
      end
    end
  end

  switch :attempt do
    on(result(:sale, [:terms, :outcome]))

    matches? &(&1 == :no_sale) do
      step :attempt, Steps.CloseWithoutOffers do
        argument(:setting, result(:setting))
      end
    end

    default do
      step :exchange, Steps.Exchange do
        argument(:setting, result(:setting))
        argument(:sale, result(:sale))
      end

      switch :rescission do
        on(result(:sale, [:governing_window]))

        matches? &(&1 == :exempt) do
          step :rescission, Steps.NoCoolingOff do
            wait_for(:exchange)
          end
        end

        default do
          await :rescission do
            signal("cooling_off.rescission")
            argument(:governing_window, result(:sale, [:governing_window]))
            timeout(&Steps.cooling_off_window/2)
            on_timeout(:return)
            wait_for(:exchange)
          end
        end
      end

      switch :contract do
        on(result(:rescission))

        matches? &(&1 in [:none, :timeout]) do
          step(:contract, Steps.ContractHolds)
        end

        default do
          step :rescind, Steps.Rescind do
            argument(:setting, result(:setting))
            argument(:exchange, result(:exchange))
          end

          step :contract, Steps.Rescinded do
            wait_for(:rescind)
          end
        end
      end

      switch :standing do
        on(result(:contract))

        matches? &(&1 == :rescinded) do
          step(:standing, {Steps.Failed, reason: :rescinded})
        end

        default do
          dispatch :conditions do
            workflow(Agency.Sale.Conditions)
            queue(:sales)
            argument(:contract_id, result(:exchange, [:contract_id]))
          end

          switch :satisfaction do
            on(result(:conditions, [:outcome]))

            matches? &(&1 == :condition_failed) do
              step :condition_failure, Steps.ConditionFailure do
                argument(:setting, result(:setting))
                argument(:exchange, result(:exchange))
              end

              step :satisfaction, {Steps.Failed, reason: :condition_failed} do
                wait_for(:condition_failure)
              end
            end

            default do
              switch :settlement do
                on(result(:setting, [:commission_trigger]))

                matches? &(&1 == :on_unconditional) do
                  step :advance_commission, Steps.AdvanceCommission do
                    argument(:setting, result(:setting))
                    argument(:exchange, result(:exchange))
                  end

                  await :settlement do
                    signal("settlement.completed")
                    timeout(Window.settlement())
                    wait_for(:advance_commission)
                  end
                end

                default do
                  await :settlement do
                    signal("settlement.completed")
                    timeout(Window.settlement())
                  end
                end
              end

              switch :conclusion do
                on(result(:settlement, [:result]))

                matches? &(&1 == :settled) do
                  step :settle, Steps.Settle do
                    argument(:setting, result(:setting))
                    argument(:exchange, result(:exchange))
                  end

                  step :conclusion, Steps.Settled do
                    argument(:settlement, result(:settle))
                  end
                end

                default do
                  step :buyer_default, Steps.BuyerDefault do
                    argument(:setting, result(:setting))
                    argument(:exchange, result(:exchange))
                  end

                  step :conclusion, {Steps.Failed, reason: :buyer_default} do
                    wait_for(:buyer_default)
                  end
                end
              end

              step :satisfaction, Steps.Reported do
                argument(:result, result(:conclusion))
              end
            end
          end

          step :standing, Steps.Reported do
            argument(:result, result(:satisfaction))
          end
        end
      end

      step :attempt, Steps.Reported do
        argument(:result, result(:standing))
      end
    end
  end

  step :succession, Steps.Succession do
    argument(:setting, result(:setting))
    argument(:attempt, result(:attempt))
  end

  switch :chain do
    on(result(:succession))

    matches? &(&1 == :report) do
      step :chain, Steps.Reported do
        argument(:result, result(:attempt))
      end
    end

    matches? &(&1 == :next_generation) do
      step :open_successor, Steps.OpenSuccessor do
        argument(:setting, result(:setting))
      end

      dispatch :next_attempt do
        workflow(Agency.Sale.Attempt)
        queue(:sales)
        argument(:sale_attempt_id, result(:open_successor, [:sale_attempt_id]))
      end

      step :chain, Steps.Reported do
        argument(:result, result(:next_attempt))
      end
    end

    default do
      step(:chain, Steps.RegisterExhausted)
    end
  end

  return(:chain)
end
