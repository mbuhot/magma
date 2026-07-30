defmodule Helpdesk.Accounts.Calculations.Permissions do
  @moduledoc """
  What a user may do, derived from their role and their grants.

  Nothing stores this. It is read from the rows that stand when it is asked for, which is what
  lets a workflow parked for a day authorize against authority given to its actor an hour ago.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _options, _context) do
    [grants: Ash.Query.select(Helpdesk.Accounts.Grant, [:permission])]
  end

  @impl true
  def calculate(users, _options, _context) do
    Enum.map(users, fn user ->
      Enum.uniq(by_role(user.role) ++ Enum.map(user.grants, & &1.permission))
    end)
  end

  defp by_role(:team_lead), do: [:reassign_tickets]
  defp by_role(:agent), do: []
end
