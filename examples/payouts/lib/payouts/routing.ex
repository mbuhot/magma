defmodule Payouts.Routing do
  @moduledoc """
  Which rail serves a currency.

  A row in config, read on every payout. Adding a currency routes the next one without a
  deploy, and the spine never learns a provider's name.
  """

  @doc "The onboarding workflow for a currency, since each rail asks for something different."
  @spec onboarding_for(map(), map()) :: module()
  def onboarding_for(%{onboarding: onboarding}, _context) do
    fetch!(:onboarding, onboarding.destination_currency)
  end

  @doc "The rail workflow for a transfer's destination currency."
  @spec rail_for(map(), map()) :: module()
  def rail_for(%{transfer: transfer}, _context) do
    fetch!(:rails, transfer.destination_currency)
  end

  @doc "Every currency config serves, and the three workflows each one is served by."
  @spec rails() :: [map()]
  def rails do
    :payouts
    |> Application.fetch_env!(:rails)
    |> Enum.map(fn {currency, rail} ->
      %{
        currency: currency,
        rail: rail,
        onboarding: Application.fetch_env!(:payouts, :onboarding)[currency],
        beneficiary: beneficiary_for(currency)
      }
    end)
    |> Enum.sort_by(& &1.currency)
  end

  @doc """
  The beneficiary registration workflow for a currency, or `nil`.

  A rail that pays the customer's own account has no entry, and a payout on it is never
  gated on a registration.
  """
  @spec beneficiary_for(String.t()) :: module() | nil
  def beneficiary_for(currency) do
    :payouts |> Application.fetch_env!(:beneficiaries) |> Map.get(currency)
  end

  defp fetch!(key, currency) do
    case Application.fetch_env!(:payouts, key) |> Map.fetch(currency) do
      {:ok, workflow} -> workflow
      :error -> raise "no rail serves #{currency}"
    end
  end
end
