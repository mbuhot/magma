defmodule Helpdesk.AuthorityTest do
  @moduledoc """
  What the actor on a durable run is allowed to do, and when that is decided.

  Every test here starts a workflow as somebody who may raise an escalation and may not act on
  one, parks it, and moves their authority while it is parked.
  """

  use Helpdesk.DataCase, async: true

  alias Helpdesk.Support.Escalation.Workflow

  setup do
    organisation = an_organisation()
    agent = a_user(organisation, "Ada")
    ticket = a_ticket(organisation, agent)

    %{organisation: organisation, agent: agent, ticket: ticket}
  end

  defp escalate(ticket, actor) do
    {:ok, workflow} = Workflow.start(ticket, "customer waiting three days", actor)
    run_escalations()

    workflow
  end

  defp approve(workflow, assignee) do
    {:ok, _signal} = Workflow.decide(workflow.id, :approved, assignee.id)
    run_escalations()
  end

  defp reject(workflow) do
    {:ok, _signal} = Workflow.decide(workflow.id, :rejected, nil)
    run_escalations()
  end

  test "a permission granted while the run was parked lets it finish", context do
    workflow = escalate(context.ticket, context.agent)
    grant(context.organisation, context.agent)

    approve(workflow, context.agent)

    assert status(workflow) == :completed
    assert reload_ticket(context.organisation, context.ticket, context.agent).status == :escalated
  end

  test "an actor holding no such permission cannot move the ticket", context do
    workflow = escalate(context.ticket, context.agent)

    approve(workflow, context.agent)

    assert status(workflow) == :failed
    assert reload_ticket(context.organisation, context.ticket, context.agent).status == :open
  end

  test "a permission taken back while the run was parked stops it", context do
    given = grant(context.organisation, context.agent)
    workflow = escalate(context.ticket, context.agent)
    revoke(context.organisation, given)

    approve(workflow, context.agent)

    assert status(workflow) == :failed
  end

  test "an escalation nobody may act on is withdrawn when the run unwinds", context do
    workflow = escalate(context.ticket, context.agent)

    approve(workflow, context.agent)

    {:ok, escalations} =
      Helpdesk.Support.list_escalations(tenant: context.organisation.id, actor: context.agent)

    assert escalations == []
    refute ":raise" in declared_tape(workflow)
  end

  test "a rejected escalation puts the ticket back where it was", context do
    grant(context.organisation, context.agent)
    other = a_user(context.organisation, "Bea")
    workflow = escalate(context.ticket, context.agent)

    reject(workflow)

    ticket = reload_ticket(context.organisation, context.ticket, context.agent)

    assert status(workflow) == :failed
    assert ticket.status == :open
    assert ticket.assignee_id == context.agent.id
    refute ticket.assignee_id == other.id
  end

  test "the role a user holds grants the same permission a grant does", context do
    manager = a_user(context.organisation, "Grace", :manager)
    workflow = escalate(context.ticket, manager)

    approve(workflow, manager)

    assert status(workflow) == :completed
  end
end
