defmodule Agency.Sale.Changes.Tell do
  @moduledoc """
  Carries an instruction to the workflow running behind the row the action was asked of.

  The row is what the caller names and what the action reads. Which workflow is presently
  carrying that row's sale is named here by its part in the sale — `:campaign`, `:attempt`,
  the gate, a sale method, the conditions — and looked up when the action runs.

      change({Tell, to: :campaign, signal: "campaign.outcome", payload: %{decision: :proceed}})

  `signal` is a name, or `{prefix, argument}` where the argument's value completes it.
  `payload` is a map, `{module, function}` called with the record and the arguments, or absent.
  `from_arguments` names arguments to carry into the payload under their own keys.
  """

  use Ash.Resource.Change

  alias Agency.Sale.Runs

  @impl true
  def change(changeset, options, _context) do
    Ash.Changeset.after_transaction(changeset, fn changeset, result ->
      with {:ok, record} <- result do
        arguments = changeset.arguments
        name = signal(options[:signal], arguments)

        :ok = tell(record, options[:to], name, payload(options, record, arguments))

        {:ok, record}
      end
    end)
  end

  defp tell(record, to, name, payload) do
    case workflow_id(to, record) do
      workflow_id when is_binary(workflow_id) ->
        {:ok, _signal} = Magma.signal(workflow_id, name, payload)
        :ok

      nil ->
        :ok
    end
  end

  defp workflow_id(:gate, listing), do: Runs.gate_id(listing.id)
  defp workflow_id(:campaign, listing), do: Runs.campaign_id(listing.id)
  defp workflow_id(:attempt, listing), do: Runs.attempt_id(listing.id)
  defp workflow_id(:conditions, listing), do: Runs.conditions_of(listing.id)
  defp workflow_id({:method, method}, listing), do: Runs.method_id(listing.id, method)
  defp workflow_id(:negotiation, offer), do: Runs.negotiation_of_offer(offer.id)

  defp signal({prefix, argument}, arguments),
    do: prefix <> to_string(Map.fetch!(arguments, argument))

  defp signal(name, _arguments) when is_binary(name), do: name

  defp payload(options, record, arguments) do
    options
    |> Keyword.get(:payload, %{})
    |> build(record, arguments)
    |> Map.merge(Map.take(arguments, Keyword.get(options, :from_arguments, [])))
  end

  defp build({module, function}, record, arguments),
    do: apply(module, function, [record, arguments])

  defp build(payload, _record, _arguments) when is_map(payload), do: payload
end
