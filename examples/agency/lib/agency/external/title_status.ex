defmodule Agency.External.TitleStatus do
  @moduledoc "Where a title search stands with the searching office."

  use Ash.Type.Enum,
    values: [
      ordered: "the search has been requested but not returned",
      clear: "the search came back with nothing encumbering the title",
      encumbered: "the search found an encumbrance against the title"
    ]
end
