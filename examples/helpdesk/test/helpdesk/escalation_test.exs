defmodule Helpdesk.EscalationTest do
  use Helpdesk.DataCase, async: true

  alias Helpdesk.Support.Escalation.Workflow

  setup do
    organisation = an_organisation()
    agent = a_user(organisation, "Ada")
    team_lead = a_user(organisation, "Grace", :team_lead)
    ticket = a_ticket(organisation, agent)

    %{organisation: organisation, agent: agent, team_lead: team_lead, ticket: ticket}
  end

  defp escalate(ticket, actor) do
    {:ok, workflow} = Workflow.start(ticket, "customer waiting three days", actor)
    run_escalations()

    workflow
  end

  defp decide(workflow, decision, decider, assignee) do
    {:ok, _signal} =
      Workflow.decide(workflow.id, decision, decider.id, assignee && assignee.id)

    run_escalations()
  end

  test "an escalation waits for a decision before the ticket moves anywhere", context do
    workflow = escalate(context.ticket, context.agent)

    assert status(workflow) == :waiting
    assert reload_ticket(context.organisation, context.ticket, context.agent).status == :open
  end

  test "a team lead's approval moves the ticket to whoever was named", context do
    workflow = escalate(context.ticket, context.team_lead)
    decide(workflow, :approved, context.team_lead, context.team_lead)

    ticket = reload_ticket(context.organisation, context.ticket, context.team_lead)

    assert status(workflow) == :completed
    assert ticket.status == :escalated
    assert ticket.assignee_id == context.team_lead.id
  end

  test "the run records every step it finished", context do
    workflow = escalate(context.ticket, context.team_lead)
    decide(workflow, :approved, context.team_lead, context.team_lead)

    assert declared_tape(workflow) == [
             ":ticket",
             ":assess",
             ":raise",
             ":approval",
             ":decider",
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

  test "giving up on a ticket takes back the escalation raised against it", context do
    workflow = escalate(context.ticket, context.agent)

    :ok = Workflow.abandon(context.ticket)
    run_escalations()

    {:ok, escalations} =
      Helpdesk.Support.list_escalations(
        tenant: context.organisation.id,
        actor: context.agent
      )

    assert status(workflow) == :cancelled
    assert escalations == []
  end

  test "a ticket nobody escalated is given up on without complaint", context do
    assert Workflow.abandon(context.ticket) == :ok
  end

  test "an escalation that was already decided stands after the ticket is given up on",
       context do
    workflow = escalate(context.ticket, context.team_lead)
    decide(workflow, :approved, context.team_lead, context.team_lead)

    :ok = Workflow.abandon(context.ticket)
    run_escalations()

    assert status(workflow) == :completed
  end

  test "the audit entry names the person the run acted as", context do
    workflow = escalate(context.ticket, context.team_lead)
    decide(workflow, :approved, context.team_lead, context.team_lead)

    {:ok, [entry]} =
      Helpdesk.Support.audit_trail(tenant: context.organisation.id, actor: context.team_lead)

    assert entry.actor_name == "Grace"
    assert entry.action == "escalation decided"
  end
end
