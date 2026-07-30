defmodule Helpdesk.IsolationTest do
  @moduledoc "What the tenant on a run scopes, and what survives the job boundary."

  use Helpdesk.DataCase, async: true

  alias Helpdesk.Support.Escalation.Workflow

  setup do
    northwind = an_organisation("Northwind")
    contoso = an_organisation("Contoso")

    %{
      northwind: northwind,
      contoso: contoso,
      ada: a_user(northwind, "Ada", :team_lead),
      bea: a_user(contoso, "Bea", :team_lead)
    }
  end

  test "a run cannot reach a ticket belonging to another organisation", context do
    theirs = a_ticket(context.contoso, context.bea)

    {:ok, workflow} =
      Magma.start(Workflow, %{ticket_id: theirs.id, reason: "not ours to see"},
        actor: %{id: context.ada.id},
        tenant: context.northwind.id
      )

    run_escalations()

    assert status(workflow) == :failed
    assert declared_tape(workflow) == []
  end

  test "the run reads the tenant it was started for, not whichever was last used", context do
    ours = a_ticket(context.northwind, context.ada, "ours")
    _theirs = a_ticket(context.contoso, context.bea, "theirs")

    {:ok, workflow} = Workflow.start(ours, "customer waiting", context.ada)
    run_escalations()

    assert %{subject: "ours", organisation: tenant} = recorded(workflow, :assess)
    assert tenant == context.northwind.id
  end

  test "the actor and the tenant come back after the run has been parked", context do
    ticket = a_ticket(context.northwind, context.ada)

    {:ok, workflow} = Workflow.start(ticket, "customer waiting", context.ada)
    run_escalations()

    assert status(workflow) == :waiting

    {:ok, _signal} = Workflow.decide(workflow.id, :approved, context.ada.id, context.ada.id)
    run_escalations()

    {:ok, [entry]} =
      Helpdesk.Support.audit_trail(tenant: context.northwind.id, actor: context.ada)

    assert status(workflow) == :completed
    assert entry.actor_name == "Ada"
    assert entry.org_id == context.northwind.id
  end

  test "the workflow row holds an identity and nothing that can go stale", context do
    ticket = a_ticket(context.northwind, context.ada)

    {:ok, workflow} = Workflow.start(ticket, "customer waiting", context.ada)

    assert workflow.actor == %{id: context.ada.id}
    assert workflow.tenant == context.northwind.id
  end

  test "an escalation another organisation raised is not on our audit trail", context do
    ours = a_ticket(context.northwind, context.ada, "ours")
    theirs = a_ticket(context.contoso, context.bea, "theirs")

    {:ok, our_run} = Workflow.start(ours, "ours", context.ada)
    {:ok, their_run} = Workflow.start(theirs, "theirs", context.bea)
    run_escalations()

    {:ok, _signal} = Workflow.decide(our_run.id, :approved, context.ada.id, context.ada.id)
    {:ok, _signal} = Workflow.decide(their_run.id, :approved, context.bea.id, context.bea.id)
    run_escalations()

    {:ok, ours_only} =
      Helpdesk.Support.audit_trail(tenant: context.northwind.id, actor: context.ada)

    assert Enum.map(ours_only, & &1.actor_name) == ["Ada"]
  end
end
