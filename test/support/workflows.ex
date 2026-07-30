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

  defmodule Prepared do
    @moduledoc false

    defmodule Middleware do
      @moduledoc false
      use Reactor.Middleware

      @impl true
      def init(context) do
        Effects.record(:middleware_init)

        if Effects.init_should_fail?() do
          {:error, "cannot prepare the context"}
        else
          {:ok, Map.put(context, :prepared, :yes)}
        end
      end
    end

    defmodule Step do
      @moduledoc false
      use Reactor.Step

      @impl true
      def run(_arguments, context, options) do
        {:ok, {Keyword.fetch!(options, :name), Map.get(context, :prepared)}}
      end

      @impl true
      def undo(_value, _arguments, context, options) do
        Effects.record({:undo, Keyword.fetch!(options, :name), Map.get(context, :prepared)})

        :ok
      end
    end

    use Reactor

    middlewares do
      middleware(Magma.Test.Workflows.Prepared.Middleware)
    end

    input(:order_id)

    step :quote, {Magma.Test.Workflows.Prepared.Step, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    step :charge, {Magma.Test.Workflows.Prepared.Step, name: :charge} do
      argument(:quote, result(:quote))
    end

    return(:charge)
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

  defmodule EndItself do
    @moduledoc "Ends the workflow row from inside the run, as a losing attempt's rival would."
    use Reactor.Step

    @impl true
    def run(_arguments, context, _options) do
      {:ok, workflow} = Magma.Store.get_workflow(context.magma.workflow_id)
      {:ok, _failed} = Magma.Store.update_workflow(workflow, :fail, %{error: :underfoot})

      {:ok, :ended}
    end
  end

  defmodule EndedUnderfoot do
    @moduledoc "Halts on a wait after the row has already been ended by something else."
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    step :ended, EndItself do
      wait_for(:quote)
    end

    await(:confirmation, signal: "confirm", block_ms: 0)

    return(:confirmation)
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

  defmodule Lapsing do
    @moduledoc "A wait whose deadline yields `:timeout` for the rest of the run to read."
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    await(:confirmation,
      signal: "confirm",
      block_ms: 0,
      timeout: 600_000,
      on_timeout: :return
    )

    step :ship, {Effect, name: :ship} do
      argument(:confirmation, result(:confirmation))
    end

    return(:ship)
  end

  defmodule Cooling do
    @moduledoc "A wait whose window is carried by the row that started it."
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)
    input(:window_ms)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    await :confirmation do
      signal("confirm")
      block_ms(0)
      timeout(&Magma.Test.Workflows.given_window/2)
      argument(:window_ms, input(:window_ms))
    end

    step :ship, {Effect, name: :ship} do
      argument(:confirmation, result(:confirmation))
    end

    return(:ship)
  end

  defmodule LenientCooling do
    @moduledoc "A carried window that yields `:timeout` for the rest of the run to read."
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)
    input(:window_ms)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    await :confirmation do
      signal("confirm")
      block_ms(0)
      on_timeout(:return)
      timeout(&Magma.Test.Workflows.given_window/2)
      argument(:window_ms, input(:window_ms))
    end

    step :ship, {Effect, name: :ship} do
      argument(:confirmation, result(:confirmation))
    end

    return(:ship)
  end

  defmodule ScaledCooling do
    @moduledoc "A carried window stretched by a jurisdiction's multiplier."
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)
    input(:window_ms)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    await :confirmation do
      signal("confirm")
      block_ms(0)
      timeout({Magma.Test.Workflows, :scaled_window, [3]})
      argument(:window_ms, input(:window_ms))
    end

    step :ship, {Effect, name: :ship} do
      argument(:confirmation, result(:confirmation))
    end

    return(:ship)
  end

  defmodule Shifting do
    @moduledoc "A wait whose window is read afresh from policy every time one is asked for."
    use Reactor, extensions: [Magma.Dsl]

    input(:order_id)

    step :quote, {Effect, name: :quote} do
      argument(:order_id, input(:order_id))
    end

    await :confirmation do
      signal("confirm")
      block_ms(0)
      timeout(&Magma.Test.Workflows.policy_window/2)
    end

    step :ship, {Effect, name: :ship} do
      argument(:confirmation, result(:confirmation))
    end

    return(:ship)
  end

  @doc false
  def given_window(%{window_ms: window_ms}, _context), do: window_ms

  @doc false
  def scaled_window(%{window_ms: window_ms}, _context, multiplier), do: window_ms * multiplier

  @doc false
  def policy_window(_arguments, _context) do
    Application.get_env(:magma, :test_window_ms, 600_000)
  end

  defmodule TimedSpine do
    @moduledoc "A dispatch whose patience for its child is carried by the transfer."
    use Reactor, extensions: [Magma.Dsl]

    input(:transfer_id)
    input(:window_ms)

    dispatch :rail do
      workflow(Magma.Test.Workflows.Rail)
      block_ms(0)
      timeout(&Magma.Test.Workflows.given_window/2)
      argument(:transfer_id, input(:transfer_id))
      argument(:window_ms, input(:window_ms))
    end

    return(:rail)
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

  defmodule MappedApproval do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:order_ids)

    map :approvals do
      source(input(:order_ids))

      await(:confirmation, signal: "confirm", block_ms: 0)

      step :charge, {Effect, name: :charge} do
        argument(:order_id, element(:approvals))
        argument(:confirmation, result(:confirmation))
      end

      return(:charge)
    end

    step :total, {Effect, name: :total} do
      argument(:approvals, result(:approvals))
    end

    return(:total)
  end

  defmodule MappedDispatch do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:transfer_ids)

    map :rails do
      source(input(:transfer_ids))

      dispatch :rail do
        workflow(Magma.Test.Workflows.Rail)
        block_ms(0)
        argument(:transfer_id, element(:rails))
      end

      return(:rail)
    end

    step :settle, {Effect, name: :settle} do
      argument(:rails, result(:rails))
    end

    return(:settle)
  end

  defmodule RefusableRail do
    @moduledoc "A rail that turns down whichever transfers config names."
    use Reactor

    input(:transfer_id)

    step :send do
      argument(:transfer_id, input(:transfer_id))
      run(&Magma.Test.Workflows.send_transfer/2)
    end

    return(:send)
  end

  @doc false
  def send_transfer(%{transfer_id: transfer_id}, _context) do
    Effects.record(:rail_send)

    if transfer_id in Application.get_env(:magma, :test_refused_transfers, []) do
      {:error, "the rail turned down #{transfer_id}"}
    else
      {:ok, {:rail_send, transfer_id}}
    end
  end

  defmodule ConcurrentDispatch do
    @moduledoc "A map whose elements each run a child, all of them in flight together."
    use Reactor, extensions: [Magma.Dsl]

    input(:transfer_ids)

    map :rails do
      source(input(:transfer_ids))
      allow_async?(true)

      dispatch :rail do
        workflow(Magma.Test.Workflows.RefusableRail)
        block_ms(0)
        argument(:transfer_id, element(:rails))
      end

      return(:rail)
    end

    step :settle, {Effect, name: :settle} do
      argument(:rails, result(:rails))
    end

    return(:settle)
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

  defmodule BranchedApproval do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:amount)

    switch :route do
      on(input(:amount))

      matches? &(&1 > 100) do
        await(:confirmation, signal: "confirm", block_ms: 0)

        step :large, {Effect, name: :large} do
          argument(:confirmation, result(:confirmation))
        end
      end

      default do
        step(:small, {Effect, name: :small})
      end
    end

    return(:route)
  end

  defmodule BranchedDispatch do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:amount)
    input(:transfer_id)

    switch :route do
      on(input(:amount))

      matches? &(&1 > 100) do
        dispatch :rail do
          workflow(Magma.Test.Workflows.Rail)
          block_ms(0)
          argument(:transfer_id, input(:transfer_id))
        end

        step :reconcile, {Effect, name: :reconcile} do
          argument(:rail, result(:rail))
        end
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

    dispatch :rail do
      workflow(&Magma.Test.Workflows.rail_for/2)
      block_ms(50)
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

  defmodule Leg do
    @moduledoc false
    use Reactor

    input(:transfer_id)

    step :body, {Effect, name: :leg_body} do
      argument(:transfer_id, input(:transfer_id))
    end

    return(:body)
  end

  defmodule LegLoop do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:transfer_id)

    dispatch :leg do
      workflow(Magma.Test.Workflows.Leg)
      block_ms(50)
      argument(:transfer_id, input(:transfer_id))
    end

    step :carry do
      argument(:transfer_id, input(:transfer_id))
      argument(:leg, result(:leg))
      run(&Magma.Test.Workflows.carry/2)
    end

    return(:carry)
  end

  @doc false
  def carry(%{transfer_id: transfer_id}, _context), do: {:ok, %{transfer_id: transfer_id}}

  defmodule Legs do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:transfer_id)

    recurse :loop, Magma.Test.Workflows.LegLoop do
      max_iterations(2)
      argument(:transfer_id, input(:transfer_id))
    end

    return(:loop)
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

  defmodule Gated do
    @moduledoc false
    use Reactor

    input(:order_id)

    step :gated, {Effect, name: :gated} do
      argument(:order_id, input(:order_id))
      where(&Magma.Test.Workflows.gate_open?/2)
    end

    step :after, {Effect, name: :after_gate} do
      wait_for(:gated)
    end

    return(:after)
  end

  @doc false
  def gate_open?(_arguments, _context), do: Application.get_env(:magma, :test_gate, true)

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
