defmodule Agency.Sale.Jurisdiction do
  @moduledoc "The state whose rules govern a property's sale."

  use Ash.Type.Enum,
    values: [
      nsw: "New South Wales",
      vic: "Victoria",
      qld: "Queensland"
    ]

  alias Agency.Sale.Jurisdiction.Policy

  @doc "The state's name, as it is written on the listing."
  @spec label(atom()) :: String.t()
  def label(jurisdiction), do: description(jurisdiction)

  @doc "The pre-marketing gate reactor for a dispatch's jurisdiction argument."
  @spec gate_for(map(), map()) :: module()
  def gate_for(%{jurisdiction: :nsw}, _context), do: Agency.Sale.Jurisdiction.NSW.Gate
  def gate_for(%{jurisdiction: :vic}, _context), do: Agency.Sale.Jurisdiction.VIC.Gate
  def gate_for(%{jurisdiction: :qld}, _context), do: Agency.Sale.Jurisdiction.QLD.Gate

  @doc "The cooling-off policy a jurisdiction applies to a contract."
  @spec cooling_off(atom()) :: Policy.t()
  def cooling_off(:nsw) do
    %Policy{business_days: 5, forfeit_rate: Decimal.new("0.0025"), auction: :exempt}
  end

  def cooling_off(:vic) do
    %Policy{business_days: 3, forfeit_rate: Decimal.new("0.002"), auction: :exempt}
  end

  def cooling_off(:qld) do
    %Policy{business_days: 5, forfeit_rate: Decimal.new("0.0025"), auction: :exempt}
  end

  @doc "The documents a jurisdiction's pre-marketing gate requires, in the order its gate awaits them."
  @spec required_documents(atom()) :: [atom()]
  def required_documents(:nsw) do
    [:contract, :title_search, :drainage_diagram, :planning_certificate]
  end

  def required_documents(:vic) do
    [:vendor_statement, :statement_of_information, :title_search]
  end

  def required_documents(:qld) do
    [:form_6, :seller_disclosure, :title_search]
  end
end
