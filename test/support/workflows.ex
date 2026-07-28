defmodule Magma.Test.Workflows do
  @moduledoc "Reactors the suite runs durably."

  alias Magma.Test.Effects

  defmodule Effect do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, options) do
      name = Keyword.fetch!(options, :name)
      Effects.record(name)

      if Effects.should_fail?(name) do
        raise "#{name} is down"
      else
        {:ok, {name, arguments}}
      end
    end
  end

  defmodule Undoable.Step do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, context, options), do: Effect.run(arguments, context, options)

    @impl true
    def undo(_value, _arguments, _context, options) do
      name = Keyword.fetch!(options, :name)

      if Effects.undo_should_fail?(name) do
        {:error, "cannot reverse #{name}"}
      else
        Effects.record({:undo, name})
        :ok
      end
    end
  end

  defmodule Undoable do
    @moduledoc false
    use Reactor

    input(:order_id)

    step :quote, {Magma.Test.Workflows.Undoable.Step, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    step :charge, {Magma.Test.Workflows.Undoable.Step, name: :charge} do
      argument(:quote, result(:quote))
    end

    step :ship, {Magma.Test.Workflows.Undoable.Step, name: :ship} do
      argument(:charge, result(:charge))
    end

    return(:ship)
  end

  defmodule Linear do
    @moduledoc false
    use Reactor

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    step :charge, {Effect, name: :charge} do
      argument(:quote, result(:quote))
    end

    step :ship, {Effect, name: :ship} do
      argument(:charge, result(:charge))
    end

    return(:ship)
  end

  defmodule Approval do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    await(:confirmation, signal: "confirm", block_ms: 50, timeout: 600_000)

    step :ship, {Effect, name: :ship} do
      argument(:confirmation, result(:confirmation))
    end

    return(:ship)
  end

  defmodule Polling do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    poll(:settlement, every: 60_000, until: &Magma.Test.Workflows.settled/2)

    return(:settlement)
  end

  @doc false
  def settled(_arguments, _context) do
    Effects.record(:settlement_check)

    if Effects.count(:settlement_check) >= 2, do: {:ok, :settled}, else: :not_yet
  end

  defmodule Mapped do
    @moduledoc false
    use Reactor

    input(:order_ids)

    map :charges do
      source(input(:order_ids))

      step :charge, {Effect, name: :charge} do
        argument(:order_id, element(:charges))
      end

      return(:charge)
    end

    step :total, {Effect, name: :total} do
      argument(:charges, result(:charges))
    end

    return(:total)
  end

  defmodule Branching do
    @moduledoc false
    use Reactor

    input(:amount)

    switch :route do
      on(input(:amount))

      matches? &(&1 > 100) do
        step(:large, {Effect, name: :large})
      end

      default do
        step(:small, {Effect, name: :small})
      end
    end

    return(:route)
  end

  defmodule Grouped do
    @moduledoc false
    use Reactor

    input(:order_id)

    group :batch do
      before_all(&Magma.Test.Workflows.note_group/3)
      after_all(&Magma.Test.Workflows.finish_group/1)

      step :inner_one, {Effect, name: :inner_one} do
        argument(:order_id, input(:order_id))
      end

      step :inner_two, {Effect, name: :inner_two} do
        argument(:one, result(:inner_one))
      end

      return(:inner_two)
    end

    step :after_group, {Effect, name: :after_group} do
      argument(:batch, result(:batch))
    end

    return(:after_group)
  end

  @doc false
  def finish_group(results), do: {:ok, results}

  @doc false
  def note_group(arguments, context, steps) do
    Effects.record(:group_planned)
    {:ok, arguments, context, steps}
  end

  defmodule Inner do
    @moduledoc false
    use Reactor

    input(:order_id)

    step :inner_step, {Effect, name: :inner_step} do
      argument(:order_id, input(:order_id))
    end

    return(:inner_step)
  end

  defmodule Composed do
    @moduledoc false
    use Reactor

    input(:order_id)

    compose :sub, Magma.Test.Workflows.Inner do
      argument(:order_id, input(:order_id))
    end

    step :after_compose, {Effect, name: :after_compose} do
      argument(:sub, result(:sub))
    end

    return(:after_compose)
  end

  defmodule Rail do
    @moduledoc false
    use Reactor

    input(:transfer_id)

    step :send, {Effect, name: :rail_send} do
      argument(:transfer_id, input(:transfer_id))
    end

    return(:send)
  end

  defmodule Spine do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:transfer_id)
    input(:currency)

    step :quote, {Effect, name: :quote} do
      argument(:transfer_id, input(:transfer_id))
    end

    step :rail, {Magma.Step.Dispatch, workflow: &Magma.Test.Workflows.rail_for/2, block_ms: 50} do
      argument(:transfer_id, input(:transfer_id))
      argument(:currency, input(:currency))
      wait_for(:quote)
    end

    step :reconcile, {Effect, name: :reconcile} do
      argument(:rail, result(:rail))
    end

    return(:reconcile)
  end

  @doc "Which rail serves a currency, read at run time. The spine names no rail itself."
  def rail_for(%{currency: currency}, _context) do
    Application.get_env(:magma, :test_rails, %{})
    |> Map.fetch!(currency)
  end

  defmodule Ephemeral do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    magma do
      retention(1)
    end

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    return(:quote)
  end

  defmodule Kept do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    magma do
      retention(:infinity)
    end

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    return(:quote)
  end

  defmodule Parallel do
    @moduledoc false
    use Reactor

    input(:order_id)

    step :left, {Effect, name: :left} do
      argument(:order_id, input(:order_id))
    end

    step :right, {Effect, name: :right} do
      argument(:order_id, input(:order_id))
    end

    step :join, {Effect, name: :join} do
      argument(:left, result(:left))
      argument(:right, result(:right))
    end

    return(:join)
  end
end
