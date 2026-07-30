defmodule Helpdesk.EscalationTest do
  use Helpdesk.DataCase, async: true

  alias Helpdesk.Support.Escalation.Workflow

  setup do
    organisation = an_organisation()
    agent = a_user(organisation, "Ada")
    manager = a_user(organisation, "Grace", :manager)
    ticket = a_ticket(organisation, agent)

    %{organisation: organisation, agent: agent, manager: manager, ticket: ticket}
  end

  defp escalate(ticket, actor) do
    {:ok, workflow} = Workflow.start(ticket, "customer waiting three days", actor)
    run_escalations()

    workflow
  end

  defp decide(workflow, decision, assignee) do
    {:ok, _signal} = Workflow.decide(workflow.id, decision, assignee && assignee.id)
    run_escalations()
  end

  test "an escalation waits for a decision before the ticket moves anywhere", context do
    workflow = escalate(context.ticket, context.agent)

    assert status(workflow) == :waiting
    assert reload_ticket(context.organisation, context.ticket, context.agent).status == :open
  end

  test "a manager's approval moves the ticket to whoever was named", context do
    workflow = escalate(context.ticket, context.manager)
    decide(workflow, :approved, context.manager)

    ticket = reload_ticket(context.organisation, context.ticket, context.manager)

    assert status(workflow) == :completed
    assert ticket.status == :escalated
    assert ticket.assignee_id == context.manager.id
  end

  test "the run records every step it finished", context do
    workflow = escalate(context.ticket, context.manager)
    decide(workflow, :approved, context.manager)

    assert declared_tape(workflow) == [
             ":ticket",
             ":assess",
             ":raise",
             ":approval",
             ":reassign",
             ":notify",
             ":outcome"
           ]
  end

  test "a plain step reads the actor and the tenant off the context", context do
    workflow = escalate(context.ticket, context.agent)

    assert %{raised_by: "Ada", organisation: tenant} = recorded(workflow, :assess)
    assert tenant == context.organisation.id
  end

  test "the audit entry names the person the run acted as", context do
    workflow = escalate(context.ticket, context.manager)
    decide(workflow, :approved, context.manager)

    {:ok, [entry]} = Helpdesk.Support.audit_trail(tenant: context.organisation.id, actor: context.manager)

    assert entry.actor_name == "Grace"
    assert entry.action == "escalation decided"
  end
end
