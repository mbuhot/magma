defmodule Magma.Type.TermTest do
  use ExUnit.Case, async: true

  alias Magma.Type.Term

  defmodule Money do
    @moduledoc false
    defstruct [:amount, :currency]
  end

  defp round_trip(value) do
    {:ok, cast} = Ash.Type.cast_input(Term, value, [])
    {:ok, stored} = Ash.Type.dump_to_native(Term, cast, [])
    {:ok, loaded} = Ash.Type.cast_stored(Term, stored, [])
    loaded
  end

  test "an atom comes back as the same atom" do
    assert round_trip(:awaiting_approval) == :awaiting_approval
  end

  test "a tuple comes back as the same tuple" do
    assert round_trip({:ok, %{outcome: :approve}}) == {:ok, %{outcome: :approve}}
  end

  test "a struct comes back as the same struct" do
    money = %Money{amount: Decimal.new("10.50"), currency: :EUR}

    assert round_trip(money) == money
  end

  test "a nested term keeps every atom and tuple inside it" do
    quote_result = %{
      rate: Decimal.new("278.35"),
      expires_at: ~U[2026-07-29 08:00:00Z],
      legs: [{:debit, :USD}, {:credit, :EUR}]
    }

    assert round_trip(quote_result) == quote_result
  end

  test "nil comes back as nil" do
    assert round_trip(nil) == nil
  end

  test "a value is stored as a binary" do
    {:ok, stored} = Ash.Type.dump_to_native(Term, {:ok, :approve}, [])

    assert is_binary(stored)
  end

  test "stored bytes that are not a term are rejected" do
    assert :error = Ash.Type.cast_stored(Term, "not a term", [])
  end

  test "a checkpoint written by code this run never loaded still replays" do
    atom_name = "magma_type_term_test_unloaded_atom"
    encoded = <<131, 119, byte_size(atom_name)::8>> <> atom_name

    assert_raise ArgumentError, fn -> :erlang.binary_to_term(encoded, [:safe]) end

    assert {:ok, loaded} = Ash.Type.cast_stored(Term, encoded, [])
    assert loaded == String.to_existing_atom(atom_name)
  end
end
