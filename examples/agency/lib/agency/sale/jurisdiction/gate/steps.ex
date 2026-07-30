defmodule Agency.Sale.Jurisdiction.Gate.Steps do
  @moduledoc false

  defmodule Satisfied do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:ok, :satisfied}
  end
end
