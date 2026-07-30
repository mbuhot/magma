defmodule Agency.Sale.Window do
  @moduledoc """
  How long each of the sale's human decisions is given, and how often an external system is
  checked, in milliseconds.
  """

  @offer_response Application.compile_env(:agency, :offer_response_window_ms, :timer.hours(48))

  @offer_deadline Application.compile_env(
                    :agency,
                    :offer_deadline_window_ms,
                    :timer.hours(24 * 21)
                  )

  @auction_day Application.compile_env(:agency, :auction_day_window_ms, :timer.hours(24 * 28))

  @cooling_off_day Application.compile_env(:agency, :cooling_off_day_ms, :timer.hours(24))

  @agency_term Application.compile_env(:agency, :agency_term_window_ms, :timer.hours(24 * 90))

  @condition_period Application.compile_env(:agency, :condition_window_ms, :timer.hours(24 * 21))

  @settlement Application.compile_env(:agency, :settlement_window_ms, :timer.hours(24 * 42))

  @poll_interval Application.compile_env(:agency, :poll_interval_ms, :timer.minutes(30))

  @settlement_days 42

  @doc "How long a buyer or vendor has to answer an offer."
  @spec offer_response() :: pos_integer()
  def offer_response, do: @offer_response

  @doc "How long a set date sale collects offers for."
  @spec offer_deadline() :: pos_integer()
  def offer_deadline, do: @offer_deadline

  @doc "How long a campaign runs before the hammer falls."
  @spec auction_day() :: pos_integer()
  def auction_day, do: @auction_day

  @doc "How long a cooling-off right of the given number of business days lasts."
  @spec cooling_off(pos_integer()) :: pos_integer()
  def cooling_off(business_days), do: business_days * @cooling_off_day

  @doc "How long the agency agreement's term runs beneath the campaign."
  @spec agency_term() :: pos_integer()
  def agency_term, do: @agency_term

  @doc "How much of an agency agreement whose term ends on the given date is left to run."
  @spec remaining_term(Date.t()) :: pos_integer()
  def remaining_term(term_end) do
    term_end |> DateTime.new!(~T[23:59:59], "Etc/UTC") |> ms_until()
  end

  @doc "How long a contract's conditions have to resolve."
  @spec condition_period() :: pos_integer()
  def condition_period, do: @condition_period

  @doc "How long a contract has between exchange and settlement."
  @spec settlement() :: pos_integer()
  def settlement, do: @settlement

  @doc "How long a poll waits between checking an external system's state."
  @spec poll_interval() :: pos_integer()
  def poll_interval, do: @poll_interval

  @doc "When an offer made now expires."
  @spec offer_expiry() :: DateTime.t()
  def offer_expiry do
    DateTime.utc_now() |> DateTime.add(@offer_response, :millisecond)
  end

  @doc "When a set date sale opened now stops taking offers."
  @spec offer_close() :: DateTime.t()
  def offer_close do
    DateTime.utc_now() |> DateTime.add(@offer_deadline, :millisecond)
  end

  @doc "The settlement date a contract exchanged on the given date names."
  @spec settlement_date(Date.t()) :: Date.t()
  def settlement_date(exchange_date), do: Date.add(exchange_date, @settlement_days)

  @doc "Milliseconds from now until the given point in time, floored so a deadline already past fires immediately."
  @spec ms_until(DateTime.t()) :: pos_integer()
  def ms_until(deadline) do
    deadline
    |> DateTime.diff(DateTime.utc_now(), :millisecond)
    |> max(1)
  end
end
