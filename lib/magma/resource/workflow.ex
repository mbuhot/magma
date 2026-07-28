defmodule Magma.Resource.Workflow do
  @moduledoc """
  Makes a resource the record of one workflow run.

  Add it to a resource in your own application and give it a table and a repo:

      defmodule MyApp.Magma.Workflow do
        use Ash.Resource,
          domain: MyApp.Magma,
          data_layer: AshPostgres.DataLayer,
          extensions: [Magma.Resource.Workflow]

        postgres do
          table "magma_workflows"
          repo MyApp.Repo
        end
      end

  The attributes and actions below are injected. Anything you add alongside them — policies,
  extra attributes, multitenancy — is yours and magma leaves it alone.
  """

  use Spark.Dsl.Extension, transformers: [Magma.Resource.Workflow.Transformer]
end
