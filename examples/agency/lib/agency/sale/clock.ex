defmodule Agency.Sale.Clock do
  @moduledoc "Business-day arithmetic against a jurisdiction's public holidays."

  @holidays [
    {~D[2026-01-01], "New Year's Day", [:nsw, :vic, :qld]},
    {~D[2026-01-26], "Australia Day", [:nsw, :vic, :qld]},
    {~D[2026-03-09], "Labour Day", [:vic]},
    {~D[2026-04-03], "Good Friday", [:nsw, :vic, :qld]},
    {~D[2026-04-06], "Easter Monday", [:nsw, :vic, :qld]},
    {~D[2026-04-25], "Anzac Day", [:nsw, :vic, :qld]},
    {~D[2026-05-04], "Labour Day", [:qld]},
    {~D[2026-06-08], "King's Birthday", [:nsw, :vic]},
    {~D[2026-10-05], "Labour Day", [:nsw]},
    {~D[2026-10-05], "King's Birthday", [:qld]},
    {~D[2026-11-03], "Melbourne Cup Day", [:vic]},
    {~D[2026-12-25], "Christmas Day", [:nsw, :vic, :qld]},
    {~D[2026-12-28], "Boxing Day observed", [:nsw, :vic, :qld]}
  ]

  @doc "The resulting date after a number of business days, and the holidays skipped along the way."
  @spec add_business_days(Date.t(), pos_integer(), atom()) :: {Date.t(), [String.t()]}
  def add_business_days(date, business_days, jurisdiction) do
    advance(date, business_days, jurisdiction, [])
  end

  @doc "Whether a date is a business day in a jurisdiction."
  @spec business_day?(Date.t(), atom()) :: boolean()
  def business_day?(date, jurisdiction) do
    day_kind(date, jurisdiction) == :business_day
  end

  defp advance(date, 0, _jurisdiction, skipped), do: {date, Enum.reverse(skipped)}

  defp advance(date, remaining, jurisdiction, skipped) do
    next_date = Date.add(date, 1)

    case day_kind(next_date, jurisdiction) do
      {:holiday, name} -> advance(next_date, remaining, jurisdiction, [name | skipped])
      :weekend -> advance(next_date, remaining, jurisdiction, skipped)
      :business_day -> advance(next_date, remaining - 1, jurisdiction, skipped)
    end
  end

  defp day_kind(date, jurisdiction) do
    cond do
      Date.day_of_week(date) in [6, 7] -> :weekend
      holiday_name(date, jurisdiction) -> {:holiday, holiday_name(date, jurisdiction)}
      true -> :business_day
    end
  end

  defp holiday_name(date, jurisdiction) do
    Enum.find_value(@holidays, fn {holiday_date, name, jurisdictions} ->
      if holiday_date == date and jurisdiction in jurisdictions, do: name
    end)
  end
end
