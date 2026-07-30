defmodule Helpdesk.Accounts.Rehydrate do
  @moduledoc """
  Turns the identity a workflow persisted into the actor its steps authorize as.

  Magma seeds `actor` and `tenant` onto the reactor context from the workflow's row, and the
  row holds only an id. Ash never loads an actor's fields on demand — an unloaded path raises
  rather than resolving — so the load has to happen before any step runs.

  `Reactor.run/4` calls this once per attempt, before the first step, and magma runs it again
  before driving any `undo/4`. A run parked for a day therefore wakes with the permissions its
  actor holds today.
  """

  use Reactor.Middleware

  alias Helpdesk.Accounts

  @impl true
  def init(%{actor: %{id: id}, tenant: tenant} = context) do
    case Accounts.get_user(id, tenant: tenant, load: [:permissions]) do
      {:ok, user} -> {:ok, %{context | actor: user}}
      {:error, reason} -> {:error, reason}
    end
  end

  def init(context), do: {:ok, context}
end
