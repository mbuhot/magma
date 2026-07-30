defmodule Magma.Type.Term do
  @moduledoc """
  An Ash type holding any Erlang term, stored as `bytea`.

  Atoms, tuples, structs, Decimals and Ash records round trip exactly, which is what lets a
  replayed step return the value the original run produced. Decoding trusts the stored bytes
  as the application's own write, so it may create an atom the running VM has never seen.
  """

  use Ash.Type

  @impl true
  def storage_type(_constraints), do: :binary

  @impl true
  def cast_input(value, _constraints), do: {:ok, value}

  @impl true
  def cast_atomic(_new_value, _constraints) do
    {:not_atomic, "a term is serialized in the application and cannot be cast atomically"}
  end

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(value, _constraints) do
    {:ok, :erlang.term_to_binary(value, [:deterministic])}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, _constraints) when is_binary(value) do
    {:ok, :erlang.binary_to_term(value)}
  rescue
    ArgumentError -> :error
  end

  def cast_stored(_value, _constraints), do: :error
end
