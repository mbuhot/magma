defmodule Magma.Step.Poll do
  @moduledoc """
  Checks a condition on an interval until it holds.

  This is the case a snooze suits: nothing will push you, so the job comes back on its own
  rather than waiting to be woken. Individual checks hold no checkpoint; the one that
  satisfies the condition does.

      step :settlement, {Magma.Step.Poll, every: :timer.seconds(30), until: &Provider.settled?/2}

  `until` receives the step's arguments and the reactor context, and answers `{:ok, value}` or
  `:not_yet`.
  """

  use Reactor.Step

  alias Magma.Run
  alias Magma.Store

  @default_every 30_000

  @impl true
  def run(arguments, context, options) do
    :ok = Run.assert_own_step!(context, "poll")

    case check(Keyword.fetch!(options, :until), arguments, context) do
      {:ok, value} -> {:ok, value}
      :not_yet -> park(context, options)
    end
  end

  defp check({m, f, a}, arguments, context), do: apply(m, f, [arguments, context | a])
  defp check(fun, arguments, context) when is_function(fun, 2), do: fun.(arguments, context)

  defp park(context, options) do
    every = Keyword.get(options, :every, @default_every)
    name = Magma.Key.label(context.current_step.name)
    deadline = DateTime.add(DateTime.utc_now(), every, :millisecond)

    {:ok, _waiter} = Store.park(workflow_id(context), name, :poll, deadline)

    {:halt, {:magma_poll, name}}
  end

  defp workflow_id(%{magma: %Run{workflow_id: id}}), do: id
end
