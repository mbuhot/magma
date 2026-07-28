defmodule Magma.Store do
  require Ash.Query

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

  @doc "Records a workflow about to run."
  @spec start_workflow(map()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  def start_workflow(attrs) do
    :workflow
    |> resource()
    |> Ash.Changeset.for_create(:start, attrs)
    |> Ash.create(authorize?: false)
  end

  @doc "One workflow by id."
  @spec get_workflow(String.t()) :: {:ok, Ash.Resource.record() | nil} | {:error, term()}
  def get_workflow(id) do
    Ash.get(resource(:workflow), id, authorize?: false, error?: false)
  end

  @doc "Moves a workflow to a state, or to a terminal one carrying its outcome."
  @spec update_workflow(Ash.Resource.record(), atom(), map()) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def update_workflow(workflow, action, attrs \\ %{}) do
    workflow
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update(authorize?: false)
  end

  @doc """
  Every checkpoint a workflow has, keyed by step key.

  One read per attempt. A step's lookup during the run is against this map rather than the
  database, and rows already taken back are absent, so the step runs again.
  """
  @spec checkpoints(String.t()) :: %{binary() => Ash.Resource.record()}
  def checkpoints(workflow_id) do
    :checkpoint
    |> resource()
    |> Ash.Query.filter(workflow_id == ^workflow_id and is_nil(undone_at))
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.step_key, &1})
  end

  @doc "Every checkpoint a workflow has that still stands, newest first."
  @spec standing(String.t()) :: [Ash.Resource.record()]
  def standing(workflow_id) do
    :checkpoint
    |> resource()
    |> Ash.Query.filter(workflow_id == ^workflow_id and is_nil(undone_at))
    |> Ash.Query.sort(id: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Writes what a step produced."
  @spec record(String.t(), term(), term()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  def record(workflow_id, name, output) do
    :checkpoint
    |> resource()
    |> Ash.Changeset.for_create(:record, %{
      workflow_id: workflow_id,
      step_key: Magma.Key.for(name),
      step_label: Magma.Key.label(name),
      output: output
    })
    |> Ash.create(authorize?: false)
  end

  @doc "Marks a checkpoint as taken back."
  @spec mark_undone(Ash.Resource.record()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  def mark_undone(checkpoint) do
    checkpoint
    |> Ash.Changeset.for_update(:mark_undone, %{})
    |> Ash.update(authorize?: false)
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
