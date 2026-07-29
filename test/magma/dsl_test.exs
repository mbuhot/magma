defmodule Magma.DslTest do
  use ExUnit.Case, async: true

  defmodule Declared do
    @moduledoc false
    use Reactor, extensions: [Magma.Dsl]

    input(:transfer_id)

    await :confirmation do
      signal("confirm")
      timeout(:timer.hours(48))
      argument(:transfer_id, input(:transfer_id))
    end

    poll :cleared do
      every(:timer.seconds(30))
      until(&Magma.DslTest.Declared.cleared?/2)
      wait_for(:confirmation)
    end

    dispatch :rail do
      workflow(&Magma.DslTest.Declared.rail_for/2)
      inputs(&Magma.DslTest.Declared.rail_inputs/2)
      queue(:rails)
      block_ms(50)
      argument(:transfer_id, input(:transfer_id))
    end

    dispatch :audit do
      workflow(Magma.DslTest.Declared)
      argument(:transfer_id, input(:transfer_id))
    end

    return(:rail)

    def cleared?(_arguments, _context), do: {:ok, :cleared}
    def rail_for(_arguments, _context), do: __MODULE__
    def rail_inputs(_arguments, _context), do: %{}
  end

  defp step(name) do
    Reactor.Info.to_struct!(Declared).steps |> Enum.find(&(&1.name == name))
  end

  test "a declared wait becomes a step that waits on the signal it names" do
    {Magma.Step.Await, options} = step(:confirmation).impl

    assert options[:signal] == "confirm"
    assert options[:timeout] == :timer.hours(48)
    assert Enum.map(step(:confirmation).arguments, & &1.name) == [:transfer_id]
  end

  test "a declared poll becomes a step that checks on the interval it names" do
    {Magma.Step.Poll, options} = step(:cleared).impl

    assert options[:every] == :timer.seconds(30)
    assert options[:until] == (&Declared.cleared?/2)
  end

  test "a declared dispatch becomes a step that runs a child workflow" do
    {Magma.Step.Dispatch, options} = step(:rail).impl

    assert options[:workflow] == (&Declared.rail_for/2)
    assert options[:inputs] == (&Declared.rail_inputs/2)
    assert options[:queue] == :rails
    assert options[:block_ms] == 50
  end

  test "a dispatch that names no inputs sends the step's arguments to its child" do
    {Magma.Step.Dispatch, options} = step(:audit).impl

    assert options[:workflow] == Magma.DslTest.Declared
    assert options[:inputs] == nil
    assert Enum.map(step(:audit).arguments, & &1.name) == [:transfer_id]
  end

  test "a declared step orders against one it reads nothing from" do
    [ordering] = step(:cleared).arguments

    assert ordering.source.name == :confirmation
  end
end
