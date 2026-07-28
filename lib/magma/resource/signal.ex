defmodule Magma.Resource.Signal do
  @moduledoc """
  Makes a resource the record of one message delivered to a workflow.

      defmodule MyApp.Magma.Signal do
        use Ash.Resource,
          domain: MyApp.Magma,
          data_layer: AshPostgres.DataLayer,
          extensions: [Magma.Resource.Signal]

        magma do
          workflow MyApp.Magma.Workflow
        end

        postgres do
          table "magma_signals"
          repo MyApp.Repo
        end
      end

  A signal that arrives before its `await` is reached waits in its row until the await runs,
  so delivery does not depend on timing. `consumed_at` is what keeps a second delivery of the
  same name distinct from the first.
  """

  use Spark.Dsl.Extension,
    sections: [Magma.Resource.Common.workflow_section()],
    transformers: [Magma.Resource.Signal.Transformer]
end
