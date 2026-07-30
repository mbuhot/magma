alias Helpdesk.Accounts
alias Helpdesk.Support

{:ok, organisations} = Accounts.list_organisations()

if organisations == [] do
  {:ok, northwind} = Accounts.open_organisation("Northwind")
  {:ok, contoso} = Accounts.open_organisation("Contoso")

  {:ok, ada} = Accounts.hire("Ada", %{role: :agent}, tenant: northwind.id)
  {:ok, grace} = Accounts.hire("Grace", %{role: :manager}, tenant: northwind.id)
  {:ok, bea} = Accounts.hire("Bea", %{role: :agent}, tenant: contoso.id)

  for {subject, assignee, organisation} <- [
        {"card declined at checkout", ada, northwind},
        {"refund never arrived", ada, northwind},
        {"cannot reset password", grace, northwind},
        {"invoice is for the wrong month", bea, contoso}
      ] do
    Support.open_ticket(%{subject: subject, assignee_id: assignee.id},
      tenant: organisation.id,
      actor: assignee
    )
  end

  IO.puts("Seeded Northwind (Ada, Grace) and Contoso (Bea).")
end
