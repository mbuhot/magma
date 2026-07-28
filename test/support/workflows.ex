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

    step(:confirmation, {Magma.Step.Await, signal: "confirm", block_ms: 50})

    step :ship, {Effect, name: :ship} do
      argument(:confirmation, result(:confirmation))
    end

    return(:ship)
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
