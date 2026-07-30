defmodule Magma.Test.Watcher do
  @moduledoc """
  A notifier on the suite's magma resources, so a test can see what the engine wrote.

  Notifications go to whichever process called `watch/0`, which is how a test tells that a write
  the engine makes inside a transaction of its own still reaches the application.
  """

  use Ash.Notifier

  @name :magma_test_watcher

  @doc "Sends this process everything the engine's writes raise, until it ends."
  @spec watch() :: :ok
  def watch do
    Process.register(self(), @name)
    :ok
  end

  @impl true
  def notify(notification) do
    case Process.whereis(@name) do
      nil -> :ok
      pid -> send(pid, {:magma_wrote, notification.resource, notification.action.name})
    end

    :ok
  end
end
