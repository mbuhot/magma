defmodule Magma.Resource.Checkpoint do
  @moduledoc """
  Makes a resource the record of one step's output.

      defmodule MyApp.Magma.Checkpoint do
        use Ash.Resource,
          domain: MyApp.Magma,
          data_layer: AshPostgres.DataLayer,
          extensions: [Magma.Resource.Checkpoint]

        magma do
          workflow MyApp.Magma.Workflow
        end

        postgres do
          table "magma_checkpoints"
          repo MyApp.Repo
        end
      end

  `step_key` is a sha256 over the deterministic encoding of the step's name, and
  `(workflow_id, step_key)` is unique. That index is both the replay lookup and what makes
  recording a step idempotent.

  `id` is a UUIDv7, so ordering by it orders the tape by completion.
  """

  use Spark.Dsl.Extension,
    sections: [Magma.Resource.Common.workflow_section()],
    transformers: [Magma.Resource.Checkpoint.Transformer]
end
