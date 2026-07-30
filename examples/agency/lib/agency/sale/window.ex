defmodule Agency.Sale.Window do
  @moduledoc "How long each of the sale's human decisions is given, in milliseconds."

  @offer_response Application.compile_env(:agency, :offer_response_window_ms, :timer.hours(48))

  @offer_deadline Application.compile_env(
                    :agency,
                    :offer_deadline_window_ms,
                    :timer.hours(24 * 21)
                  )

  @vendor_decision Application.compile_env(
                     :agency,
                     :vendor_decision_window_ms,
                     :timer.hours(24)
                   )

  @auction_day Application.compile_env(:agency, :auction_day_window_ms, :timer.hours(24 * 28))

  @doc "How long a buyer or vendor has to answer an offer."
  @spec offer_response() :: pos_integer()
  def offer_response, do: @offer_response

  @doc "How long a set date sale collects offers for."
  @spec offer_deadline() :: pos_integer()
  def offer_deadline, do: @offer_deadline

  @doc "How long the vendor has to pick between the offers that came back."
  @spec vendor_decision() :: pos_integer()
  def vendor_decision, do: @vendor_decision

  @doc "How long a campaign runs before the hammer falls."
  @spec auction_day() :: pos_integer()
  def auction_day, do: @auction_day

  @doc "When an offer made now expires."
  @spec offer_expiry() :: DateTime.t()
  def offer_expiry do
    DateTime.utc_now() |> DateTime.add(@offer_response, :millisecond)
  end
end
