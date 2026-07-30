defmodule Helpdesk.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Magma.Testing, repo: Helpdesk.Repo

      import Helpdesk.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Helpdesk.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    :ok
  end

  @doc "An organisation, which is to say a tenant."
  def an_organisation(name \\ "Northwind") do
    {:ok, organisation} = Helpdesk.Accounts.open_organisation(name)

    organisation
  end

  @doc "Somebody in an organisation, holding whatever their role holds and nothing more."
  def a_user(organisation, name, role \\ :agent) do
    {:ok, user} =
      Helpdesk.Accounts.hire(name, %{role: role}, tenant: organisation.id)

    user
  end

  @doc "A ticket sitting with whoever opened it."
  def a_ticket(organisation, assignee, subject \\ "card declined") do
    {:ok, ticket} =
      Helpdesk.Support.open_ticket(%{subject: subject, assignee_id: assignee.id},
        tenant: organisation.id,
        actor: assignee
      )

    ticket
  end

  @doc "Gives a user a capability, the way a console button would."
  def grant(organisation, user, permission \\ :reassign_tickets) do
    {:ok, grant} =
      Helpdesk.Accounts.grant(user.id, permission, tenant: organisation.id)

    grant
  end

  @doc "Takes one back."
  def revoke(organisation, grant) do
    :ok = Helpdesk.Accounts.revoke(grant, tenant: organisation.id)

    :ok
  end

  @doc "The ticket as it stands, read as somebody who may see it."
  def reload_ticket(organisation, ticket, actor) do
    {:ok, reloaded} =
      Helpdesk.Support.get_ticket(ticket.id, tenant: organisation.id, actor: actor)

    reloaded
  end

  @doc "Runs every escalation job that is ready."
  def run_escalations, do: Magma.Testing.run_workflows(queue: :escalations)

  @doc """
  The steps the workflow declares, in the order they finished.

  An `Ash.Reactor` action entity builds a step of its own to gather the action's input, and
  those carry generated names. They checkpoint like anything else, and two of them with
  nothing between them can finish either way round, so the shape worth pinning is the one the
  DSL names.
  """
  def declared_tape(workflow) do
    workflow |> Magma.Testing.tape() |> Enum.filter(&String.starts_with?(&1, ":"))
  end
end
