defmodule Magma.Key do
  @moduledoc false

  # How a step is identified across attempts.
  #
  # A step's identity is its name, and `%Reactor.Step{name: any}` means that name is an
  # arbitrary term — an atom for a declared step, a tuple like
  # `{Reactor.Step.Map, outer, inner, index}` for one a composite generated.
  #
  # The key is a digest of the name's canonical encoding, which gives a fixed width for a term
  # of unbounded size. `:deterministic` is what makes it canonical: the default encoding varies
  # through atom cache references and map key ordering, and would otherwise hash one name two
  # ways across attempts.

  @doc "The checkpoint key for a step name."
  @spec for(term()) :: binary()
  def for(name), do: :crypto.hash(:sha256, :erlang.term_to_binary(name, [:deterministic]))

  @doc """
  A stable id for the child a step dispatches.

  Derived from the parent and the step, so a replay finds the child already running rather
  than starting a second one.
  """
  @spec child_id(String.t(), term()) :: String.t()
  def child_id(parent_workflow_id, step_name) do
    <<a::48, _v::4, b::12, _var::2, c::62, _rest::binary>> =
      :crypto.hash(:sha256, parent_workflow_id <> label(step_name))

    <<a::48, 7::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> = hex
      Enum.join([p1, p2, p3, p4, p5], "-")
    end)
  end

  @doc "A readable rendering of a step name, for the console and for SQL."
  @spec label(term()) :: String.t()
  def label(name) when is_atom(name), do: inspect(name)
  def label(name), do: inspect(name, limit: :infinity, printable_limit: 4_000)
end
