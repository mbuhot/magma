defmodule Agency.Sale.DocumentKind do
  @moduledoc "A category of compliance document a jurisdiction's gate can require."

  use Ash.Type.Enum,
    values: [
      contract: "the vendor's solicitor's prepared contract",
      title_search: "a search of the property's title",
      drainage_diagram: "a diagram of the property's drainage",
      planning_certificate: "a certificate of the property's planning status",
      vendor_statement: "the vendor's statement of the property, required in Victoria",
      statement_of_information: "the estimated selling price statement required in Victoria",
      form_6: "the Queensland appointment form",
      seller_disclosure: "the Queensland seller disclosure statement"
    ]

  @doc "How the kind is written on screen."
  @spec label(atom()) :: String.t()
  def label(:contract), do: "Contract of sale prepared"
  def label(:title_search), do: "Title search"
  def label(:drainage_diagram), do: "Drainage diagram"
  def label(:planning_certificate), do: "Planning certificate"
  def label(:vendor_statement), do: "Vendor statement"
  def label(:statement_of_information), do: "Statement of information"
  def label(:form_6), do: "Form 6 appointment"
  def label(:seller_disclosure), do: "Seller disclosure statement"
end
