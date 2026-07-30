alias Helpdesk.Accounts
alias Helpdesk.Support

{:ok, organisations} = Accounts.list_organisations()

teams = [
  {"Northwind Traders",
   [
     {"Ada Lovelace", :agent},
     {"Ben Okri", :agent},
     {"Grace Hopper", :team_lead}
   ],
   [
     {"Card declined at checkout", "Ada Lovelace"},
     {"Refund never arrived", "Ada Lovelace"},
     {"Cannot reset my password", "Ben Okri"},
     {"Duplicate charge on invoice 4471", "Ben Okri"},
     {"Delivery address will not save", "Grace Hopper"}
   ]},
  {"Contoso Freight",
   [
     {"Bea Nkemelu", :agent},
     {"Carlos Mendes", :agent},
     {"Dana Whitfield", :team_lead}
   ],
   [
     {"Invoice is for the wrong month", "Bea Nkemelu"},
     {"Tracking number returns nothing", "Bea Nkemelu"},
     {"Customs paperwork rejected twice", "Carlos Mendes"},
     {"Quote expired before approval", "Dana Whitfield"}
   ]}
]

if organisations == [] do
  for {name, people, tickets} <- teams do
    {:ok, organisation} = Accounts.open_organisation(name)

    hired =
      Map.new(people, fn {person, role} ->
        {:ok, user} = Accounts.hire(person, %{role: role}, tenant: organisation.id)

        {person, user}
      end)

    for {subject, assignee} <- tickets do
      user = Map.fetch!(hired, assignee)

      Support.open_ticket(%{subject: subject, assignee_id: user.id},
        tenant: organisation.id,
        actor: user
      )
    end

    IO.puts("Seeded #{name} with #{map_size(hired)} people and #{length(tickets)} tickets.")
  end
end
