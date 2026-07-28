defmodule Magma.Store do
  @moduledoc """
  Where magma's rows live, and every read and write against them.

  The application owns the resources. Magma is told which domain they are in and works out
  which resource plays which role from the extension each one carries:

      config :magma, domain: MyApp.Magma, repo: MyApp.Repo

  Every call here runs at `authorize?: false`. These rows are engine bookkeeping and sit
  beneath whatever policies the application puts on them.
  """

  @roles %{
    workflow: Magma.Resource.Workflow,
    checkpoint: Magma.Resource.Checkpoint,
    signal: Magma.Resource.Signal,
    waiter: Magma.Resource.Waiter
  }

  @type role :: :workflow | :checkpoint | :signal | :waiter

  @doc "The domain the application put magma's resources in."
  @spec domain() :: module()
  def domain do
    Application.get_env(:magma, :domain) ||
      raise """
      magma has no domain configured. Point it at the domain holding your magma resources:

          config :magma, domain: MyApp.Magma, repo: MyApp.Repo

      `mix magma.install` writes the resources and this config for you.
      """
  end

  @doc "The repo magma's rows are written through."
  @spec repo() :: module()
  def repo do
    Application.get_env(:magma, :repo) ||
      raise "magma has no repo configured. Set `config :magma, repo: MyApp.Repo`."
  end

  @doc "The resource playing a role, found by the magma extension it carries."
  @spec resource(role(), module()) :: module()
  def resource(role, domain \\ nil) do
    domain = domain || domain()
    key = {__MODULE__, domain, role}

    case :persistent_term.get(key, :miss) do
      :miss ->
        found = find_resource(role, domain)
        :persistent_term.put(key, found)
        found

      found ->
        found
    end
  end

  defp find_resource(role, domain) do
    extension = Map.fetch!(@roles, role)

    domain
    |> Ash.Domain.Info.resources()
    |> Enum.find(&(extension in Spark.extensions(&1)))
    |> case do
      nil -> raise no_resource_message(role, domain, extension)
      resource -> resource
    end
  end

  defp no_resource_message(role, domain, extension) do
    """
    magma found no #{role} resource in #{inspect(domain)}.

    One resource in that domain has to carry #{inspect(extension)}:

        defmodule #{inspect(domain)}.#{role |> Atom.to_string() |> Macro.camelize()} do
          use Ash.Resource,
            domain: #{inspect(domain)},
            data_layer: AshPostgres.DataLayer,
            extensions: [#{inspect(extension)}]
        end

    `mix magma.install` writes all four for you.
    """
  end
end
