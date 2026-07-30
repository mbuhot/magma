defmodule Magma.Store do
  require Ash.Expr
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

  @doc """
  Records a workflow about to run.

  Fails when the id is already taken. A caller that derives an id asks for the workflow first
  and starts one only if there is none, so reaching a collision here means two callers raced
  for the same logical workflow — one of them wins and the other is told so.
  """
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

  @doc """
  One workflow by id, held against anything else that would move it.

  Only meaningful inside a transaction, and what it buys is that a delivery deciding whether to
  bring a workflow back and an attempt deciding to park it cannot each act on what the other
  is about to write.
  """
  @spec lock_workflow(String.t()) :: {:ok, Ash.Resource.record() | nil} | {:error, term()}
  def lock_workflow(id) do
    :workflow
    |> resource()
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  @doc """
  Claims a workflow for one attempt, if nothing else holds it.

  A claim is free when nobody holds it, when the lease on it has lapsed, or when the job asking
  is the job already holding it — a retry of a crashed attempt takes its own claim back rather
  than waiting the lease out.

  The claim is what keeps a workflow to one attempt at a time. Everything else asking for it is
  told, and comes back.
  """
  @spec claim_workflow(Ash.Resource.record(), integer() | nil, pos_integer()) ::
          {:ok, Ash.Resource.record()} | :taken
  def claim_workflow(workflow, job_id, lease_ms) do
    lapsed = DateTime.add(DateTime.utc_now(), -lease_ms, :millisecond)

    workflow
    |> Ash.Changeset.for_update(:claim, %{claimed_by: job_id})
    |> Ash.Changeset.filter(free(job_id, lapsed))
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, claimed} -> {:ok, claimed}
      {:error, _taken} -> :taken
    end
  end

  # A job with no id of its own — one driven straight from a test — cannot recognise a claim as
  # its own, since every such job would recognise every other one's.
  defp free(nil, lapsed) do
    Ash.Expr.expr(is_nil(claimed_at) or claimed_at < ^lapsed)
  end

  defp free(job_id, lapsed) do
    Ash.Expr.expr(is_nil(claimed_at) or claimed_at < ^lapsed or claimed_by == ^job_id)
  end

  @doc "Gives a claim back, so the next job for the workflow can take it."
  @spec release_claim(Ash.Resource.record()) :: :ok
  def release_claim(workflow) do
    workflow
    |> Ash.Changeset.for_update(:release_claim, %{})
    |> Ash.update(authorize?: false)

    :ok
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
  Writes the failure a run met, leaving its status alone.

  A run that goes on to roll back has this on the record before the first checkpoint is taken
  back, so the cause is there for whichever attempt ends the workflow.
  """
  @spec record_error(String.t(), term()) :: :ok | {:error, term()}
  def record_error(workflow_id, error) do
    case get_workflow(workflow_id) do
      {:ok, nil} ->
        :ok

      {:ok, workflow} ->
        with {:ok, _recorded} <- update_workflow(workflow, :record_error, %{error: error}),
             do: :ok

      {:error, reason} ->
        {:error, reason}
    end
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

  @doc """
  Writes what a step produced.

  Two attempts of one workflow can reach the same step, and the unique index settles which
  recording stands. The attempt that lost is handed the one that won, so both carry the same
  output on to everything downstream.
  """
  @spec record(String.t(), term(), term()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  def record(workflow_id, name, output) do
    key = Magma.Key.for(name)

    :checkpoint
    |> resource()
    |> Ash.Changeset.for_create(:record, %{
      workflow_id: workflow_id,
      step_key: key,
      step_label: Magma.Key.label(name),
      output: output
    })
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, checkpoint} -> {:ok, checkpoint}
      {:error, error} -> adopt(workflow_id, key, error)
    end
  end

  defp adopt(workflow_id, key, error) do
    case workflow_id |> standing() |> Enum.find(&(&1.step_key == key)) do
      nil -> {:error, error}
      checkpoint -> {:ok, checkpoint}
    end
  end

  @doc """
  Claims a checkpoint for undoing, if nothing else already has it.

  The mark goes on before the undo runs, conditional on it still being absent, so two
  rollbacks racing over one workflow cannot both take the same step back. Forward progress has
  the unique index for this; a rollback has the claim.
  """
  @spec claim_undo(Ash.Resource.record()) :: {:ok, Ash.Resource.record()} | :taken
  def claim_undo(checkpoint) do
    checkpoint
    |> Ash.Changeset.for_update(:claim_undo, %{})
    |> Ash.Changeset.filter(Ash.Expr.expr(is_nil(undone_at)))
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, claimed} -> {:ok, claimed}
      {:error, _stale} -> :taken
    end
  end

  @doc "Gives a claim back, so a checkpoint whose undo failed still stands."
  @spec release_undo(Ash.Resource.record()) :: :ok
  def release_undo(checkpoint) do
    checkpoint
    |> Ash.Changeset.for_update(:release_undo, %{})
    |> Ash.update(authorize?: false)

    :ok
  end

  @doc "Marks a checkpoint as taken back."
  @spec mark_undone(Ash.Resource.record()) :: {:ok, Ash.Resource.record()} | {:error, term()}
  def mark_undone(checkpoint) do
    checkpoint
    |> Ash.Changeset.for_update(:mark_undone, %{})
    |> Ash.update(authorize?: false)
  end

  @doc "The oldest signal of a name a workflow has not taken yet."
  @spec pending_signal(String.t(), String.t()) :: Ash.Resource.record() | nil
  def pending_signal(workflow_id, name) do
    :signal
    |> resource()
    |> Ash.Query.filter(workflow_id == ^workflow_id and name == ^name and is_nil(consumed_at))
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> List.first()
  end

  @doc """
  Takes a signal, so a second delivery of the name stays distinct from this one.

  Conditional on the signal still being untaken, so two attempts of one workflow reaching the
  same wait cannot both be answered by it. The one that loses is told, and looks for the next.
  """
  @spec consume_signal(Ash.Resource.record()) :: {:ok, Ash.Resource.record()} | :taken
  def consume_signal(signal) do
    signal
    |> Ash.Changeset.for_update(:consume, %{})
    |> Ash.Changeset.filter(Ash.Expr.expr(is_nil(consumed_at)))
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, consumed} -> {:ok, consumed}
      {:error, _stale} -> :taken
    end
  end

  @doc "Records a signal for a workflow."
  @spec deliver_signal(String.t(), String.t(), term()) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def deliver_signal(workflow_id, name, payload) do
    :signal
    |> resource()
    |> Ash.Changeset.for_create(:deliver, %{
      workflow_id: workflow_id,
      name: name,
      payload: payload
    })
    |> Ash.create(authorize?: false)
  end

  @doc "Records that a workflow is parked, and on what."
  @spec park(String.t(), String.t(), atom(), DateTime.t() | nil) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def park(workflow_id, name, kind, deadline) do
    :waiter
    |> resource()
    |> Ash.Changeset.for_create(:park, %{
      workflow_id: workflow_id,
      name: name,
      kind: kind,
      deadline: deadline
    })
    |> Ash.create(authorize?: false)
  end

  @doc "Everything a workflow is currently parked on."
  @spec waiters(String.t()) :: [Ash.Resource.record()]
  def waiters(workflow_id) do
    :waiter
    |> resource()
    |> Ash.Query.filter(workflow_id == ^workflow_id)
    |> Ash.read!(authorize?: false)
  end

  @doc "The wait a workflow holds on a name, if it holds one."
  @spec waiter(String.t(), String.t()) :: Ash.Resource.record() | nil
  def waiter(workflow_id, name) do
    workflow_id |> waiters() |> Enum.find(&(&1.name == name))
  end

  @doc "Whether a workflow is parked on a name."
  @spec waiting_on?(String.t(), String.t()) :: boolean()
  def waiting_on?(workflow_id, name) do
    waiter(workflow_id, name) != nil
  end

  @doc "Clears a wait that has been answered."
  @spec release(String.t(), String.t()) :: :ok
  def release(workflow_id, name) do
    workflow_id
    |> waiters()
    |> Enum.filter(&(&1.name == name))
    |> Enum.each(&forget/1)

    :ok
  end

  @doc """
  Clears every wait a workflow holds.

  A workflow that has ended is parked on nothing. Two attempts racing can leave one of them
  parking on a signal the other has already taken, and this is what takes that back.
  """
  @spec release_all(String.t()) :: :ok
  def release_all(workflow_id) do
    workflow_id
    |> waiters()
    |> Enum.each(&forget/1)

    :ok
  end

  # A wait is read and then cleared, and another attempt of the same workflow can clear it in
  # between. A row already gone is the outcome this asked for, so it is not an error.
  defp forget(waiter) do
    case Ash.destroy(waiter, authorize?: false) do
      :ok -> :ok
      {:error, error} -> if gone?(error), do: :ok, else: raise(error)
    end
  end

  defp gone?(%Ash.Error.Changes.StaleRecord{}), do: true
  defp gone?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &gone?/1)
  defp gone?(_error), do: false

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
