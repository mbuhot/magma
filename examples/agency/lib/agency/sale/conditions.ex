defmodule Agency.Sale.Conditions do
  @moduledoc """
  The conditions an exchanged contract must satisfy before it can settle.

  Finance, inspection and title each answer on their own signal, so they resolve in any order
  and the contract goes unconditional on the last of them. One that resolves against the buyer
  is what the caller reads back as a condition failure.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Agency.Sale.Conditions.Steps
  alias Agency.Sale.Window

  magma do
    queue(:sales)
  end

  input(:contract_id)

  await :finance do
    signal("condition.finance")
    timeout(Window.condition_period())
  end

  step :finance_condition, {Steps.Resolve, kind: :finance} do
    argument(:contract_id, input(:contract_id))
    argument(:response, result(:finance))
  end

  await :inspection do
    signal("condition.inspection")
    timeout(Window.condition_period())
  end

  step :inspection_condition, {Steps.Resolve, kind: :inspection} do
    argument(:contract_id, input(:contract_id))
    argument(:response, result(:inspection))
  end

  await :title do
    signal("condition.title")
    timeout(Window.condition_period())
  end

  step :title_condition, {Steps.Resolve, kind: :title} do
    argument(:contract_id, input(:contract_id))
    argument(:response, result(:title))
  end

  step :resolution, Steps.Resolution do
    argument(:finance, result(:finance_condition))
    argument(:inspection, result(:inspection_condition))
    argument(:title, result(:title_condition))
  end

  switch :outcome do
    on(result(:resolution, [:status]))

    matches? &(&1 == :satisfied) do
      step :unconditional, Steps.GoUnconditional do
        argument(:contract_id, input(:contract_id))
      end

      step :outcome, Steps.Unconditional do
        wait_for(:unconditional)
      end
    end

    default do
      step :outcome, Steps.Failed do
        argument(:resolution, result(:resolution))
      end
    end
  end

  return(:outcome)
end
