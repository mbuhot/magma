defmodule Magma.Step.Await do
  @moduledoc """
  Waits for a signal, briefly in this process and then not at all.

  A signal already delivered is taken straight away, so one that arrives before the await is
  reached is a non-event. Otherwise the step parks, listens, re-checks to close the race, and
  blocks for `block_ms`. A signal landing in that window answers a webhook expected in seconds
  without paying for a replay.

  Past the window it halts. The workflow becomes a row holding no process and no job, and
  `Magma.signal/3` brings it back.

  A `timeout` is measured once, when the wait first parks, and the waiter row holds it. Every
  later attempt reads that same instant back, so the deadline stands however often the wait is
  revisited, and the run fails or yields `:timeout` at it.

  A `timeout` is a count of milliseconds, or a two-arity function or MFA over the step's
  arguments and context that answers with one. A resolved window lets a cooling-off period come
  from the row that started the wait. It is asked only on the attempt that parks, so what it
  answers later cannot move a deadline already set.
  """

  use Reactor.Step

  alias Magma.Run
  alias Magma.Store

  @default_block_ms 5_000

  @impl true
  def run(arguments, context, options) do
    :ok = Run.assert_own_step!(context, "await")
    name = Keyword.fetch!(options, :signal)
    workflow_id = workflow_id(context)

    case take(workflow_id, name) do
      {:ok, payload} -> {:ok, payload}
      :none -> park_and_block(workflow_id, name, arguments, context, options)
    end
  end

  defp park_and_block(workflow_id, name, arguments, context, options) do
    deadline = park(workflow_id, name, arguments, context, options)

    Magma.Notifier.listen(workflow_id, name)

    case take(workflow_id, name) do
      {:ok, payload} -> {:ok, payload}
      :none -> block(workflow_id, name, options, deadline)
    end
  end

  defp block(workflow_id, name, options, deadline) do
    block_ms = block_ms(options)

    receive do
      {:magma_signal, ^workflow_id, ^name} -> :woken
    after
      block_ms -> :timeout
    end

    case take(workflow_id, name) do
      {:ok, payload} -> {:ok, payload}
      :none -> expired_or_halt(workflow_id, name, options, deadline)
    end
  end

  defp expired_or_halt(workflow_id, name, options, deadline) do
    if deadline && DateTime.compare(DateTime.utc_now(), deadline) != :lt do
      timeout(workflow_id, name, options)
    else
      {:halt, {:magma_await, name}}
    end
  end

  defp timeout(workflow_id, name, options) do
    :ok = Store.release(workflow_id, name)

    case Keyword.get(options, :on_timeout, :error) do
      :return -> {:ok, :timeout}
      :error -> {:error, %Magma.TimeoutError{signal: name}}
    end
  end

  # A signal is taken conditionally, so an attempt that finds one another attempt of the same
  # workflow has already taken goes looking for the next.
  defp take(workflow_id, name) do
    case Store.pending_signal(workflow_id, name) do
      nil ->
        :none

      signal ->
        case Store.consume_signal(signal) do
          {:ok, _consumed} ->
            :ok = Store.release(workflow_id, name)
            {:ok, signal.payload}

          :taken ->
            take(workflow_id, name)
        end
    end
  end

  @doc """
  How long a wait holds its process before releasing the job.

  How long a deployment is willing to hold a worker is deployment policy, so a wait that names
  no window takes the one in config. A test suite sets it to zero and pays nothing for a wait
  it is about to answer itself.
  """
  @spec block_ms(keyword()) :: non_neg_integer()
  def block_ms(options) do
    case Keyword.get(options, :block_ms) do
      nil -> Application.get_env(:magma, :block_ms, @default_block_ms)
      ms -> ms
    end
  end

  # The deadline of a wait already parked is the one it was parked with, so a window measured
  # once is the window every later attempt reads. A fresh one is measured only by the attempt
  # that parks, which is also the only attempt that needs a job scheduled at it.
  defp park(workflow_id, name, arguments, context, options) do
    case Store.waiter(workflow_id, name) do
      %{deadline: deadline} ->
        deadline

      nil ->
        deadline = deadline(arguments, context, options)
        {:ok, _waiter} = Store.park(workflow_id, name, :signal, deadline)
        :ok = Magma.Api.schedule_timeout(workflow_id, deadline)
        deadline
    end
  end

  defp deadline(arguments, context, options) do
    case resolve(Keyword.get(options, :timeout), arguments, context) do
      nil -> nil
      ms -> DateTime.add(DateTime.utc_now(), ms, :millisecond)
    end
  end

  @doc """
  A timeout as the caller wrote it, answered as milliseconds.
  """
  @spec resolve(nil | pos_integer() | (map(), map() -> pos_integer()) | mfa(), map(), map()) ::
          nil | pos_integer()
  def resolve(fun, arguments, context) when is_function(fun, 2), do: fun.(arguments, context)
  def resolve({m, f, a}, arguments, context), do: apply(m, f, [arguments, context | a])
  def resolve(ms, _arguments, _context), do: ms

  defp workflow_id(%{magma: %Run{workflow_id: id}}), do: id
end
