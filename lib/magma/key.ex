defmodule Magma.Key do
  @moduledoc """
  How a step is identified across attempts.

  A step's identity is its name, and `%Reactor.Step{name: any}` means that name is an
  arbitrary term — an atom for a declared step, a tuple like
  `{Reactor.Step.Map, outer, inner, index}` for one a composite generated.

  The key is a digest of the name's canonical encoding, which gives a fixed width for a term
  of unbounded size. `:deterministic` is what makes it canonical: the default encoding varies
  through atom cache references and map key ordering, and would otherwise hash one name two
  ways across attempts.
  """

  @doc "The checkpoint key for a step name."
  @spec for(term()) :: binary()
  def for(name), do: :crypto.hash(:sha256, :erlang.term_to_binary(name, [:deterministic]))

  @doc "A readable rendering of a step name, for the console and for SQL."
  @spec label(term()) :: String.t()
  def label(name) when is_atom(name), do: inspect(name)
  def label(name), do: inspect(name, limit: :infinity, printable_limit: 4_000)
end
