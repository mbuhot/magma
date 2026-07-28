defmodule Magma.Resource.Waiter do
  @moduledoc """
  Makes a resource the record of what a parked workflow is waiting on.

      defmodule MyApp.Magma.Waiter do
        use Ash.Resource,
          domain: MyApp.Magma,
          data_layer: AshPostgres.DataLayer,
          extensions: [Magma.Resource.Waiter]

        magma do
          workflow MyApp.Magma.Workflow
        end

        postgres do
          table "magma_waiters"
          repo MyApp.Repo
        end
      end

  A waiter row is written before an `await` halts, so the worker learns why a run stopped from
  committed state rather than from the halt itself, and `Magma.signal/3` learns whether a
  resume job is worth inserting.
  """

  use Spark.Dsl.Extension,
    sections: [Magma.Resource.Common.workflow_section()],
    transformers: [Magma.Resource.Waiter.Transformer]
end
