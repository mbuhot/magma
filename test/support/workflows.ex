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

    step(:confirmation, {Magma.Step.Await, signal: "confirm", block_ms: 50, timeout: 600_000})

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

    step(:settlement, {Magma.Step.Poll, every: 60_000, until: &Magma.Test.Workflows.settled/2})

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
