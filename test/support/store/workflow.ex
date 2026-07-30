defmodule Magma.Test.Store.Workflow do
  @moduledoc "The workflow resource the suite runs against, written the way an application would."

  use Ash.Resource,
    domain: Magma.Test.Store,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Magma.Test.Watcher],
    extensions: [Magma.Resource.Workflow]

  postgres do
    table "magma_workflows"
    repo Magma.TestRepo
  end
end
