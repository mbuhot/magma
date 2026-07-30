defmodule Agency.Sale.Money do
  @moduledoc "Cents arithmetic over the rates an agreement and a jurisdiction carry."

  @doc "The commission an agreement's percentage rate earns on a price."
  @spec commission(integer(), Decimal.t()) :: integer()
  def commission(price, commission_rate) do
    price
    |> Decimal.new()
    |> Decimal.mult(commission_rate)
    |> Decimal.div(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  @doc "The share of a price a jurisdiction lets the vendor keep when a buyer rescinds."
  @spec forfeit(integer(), Decimal.t()) :: integer()
  def forfeit(price, forfeit_rate) do
    price
    |> Decimal.new()
    |> Decimal.mult(forfeit_rate)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end
end
