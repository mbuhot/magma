defmodule Magma.Resource.Common do
  @moduledoc false

  alias Ash.Resource.Builder

  @workflow_section %Spark.Dsl.Section{
    name: :magma,
    describe: "Which resource in this application carries the workflow role.",
    examples: ["magma do\n  workflow MyApp.Magma.Workflow\nend"],
    schema: [
      workflow: [
        type: {:spark, Ash.Resource},
        required: true,
        doc: "The resource carrying `Magma.Resource.Workflow`."
      ]
    ]
  }

  @doc "The `magma do workflow ... end` section the dependent resources carry."
  def workflow_section, do: @workflow_section

  @doc "A primary key that also carries the row's order, since UUIDv7 embeds its timestamp."
  def add_id(dsl_state) do
    Builder.add_new_attribute(dsl_state, :id, :uuid_v7,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      default: &Ash.UUIDv7.generate/0
    )
  end

  @doc "The workflow a row belongs to, read from the resource's `magma` section."
  def add_workflow({:ok, dsl_state}), do: add_workflow(dsl_state)
  def add_workflow({:error, _reason} = error), do: error

  def add_workflow(dsl_state) do
    workflow = Spark.Dsl.Transformer.get_option(dsl_state, [:magma], :workflow)

    Builder.add_new_relationship(dsl_state, :belongs_to, :workflow, workflow,
      allow_nil?: false,
      public?: true,
      attribute_writable?: true
    )
  end

  @doc "A change setting one attribute to a fixed value."
  def set(attribute, value) do
    {:ok, change} =
      Builder.build_action_change(
        {Ash.Resource.Change.SetAttribute, attribute: attribute, value: value}
      )

    change
  end
end
