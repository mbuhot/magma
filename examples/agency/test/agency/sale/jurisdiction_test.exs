defmodule Agency.Sale.JurisdictionTest do
  use ExUnit.Case, async: true

  alias Agency.Sale.Jurisdiction

  test "New South Wales dispatches its own pre-marketing gate" do
    assert Jurisdiction.gate_for(%{jurisdiction: :nsw}, %{}) ==
             Agency.Sale.Jurisdiction.NSW.Gate
  end

  test "Victoria dispatches its own pre-marketing gate" do
    assert Jurisdiction.gate_for(%{jurisdiction: :vic}, %{}) ==
             Agency.Sale.Jurisdiction.VIC.Gate
  end

  test "Queensland dispatches its own pre-marketing gate" do
    assert Jurisdiction.gate_for(%{jurisdiction: :qld}, %{}) ==
             Agency.Sale.Jurisdiction.QLD.Gate
  end

  test "New South Wales cools off over 5 business days at a 0.25% forfeit, exempt at auction" do
    assert Jurisdiction.cooling_off(:nsw) == %Jurisdiction.Policy{
             business_days: 5,
             forfeit_rate: Decimal.new("0.0025"),
             auction: :exempt
           }
  end

  test "Victoria cools off over 3 business days at a 0.2% forfeit, exempt at auction" do
    assert Jurisdiction.cooling_off(:vic) == %Jurisdiction.Policy{
             business_days: 3,
             forfeit_rate: Decimal.new("0.002"),
             auction: :exempt
           }
  end

  test "Queensland cools off over 5 business days at a 0.25% forfeit, exempt at auction" do
    assert Jurisdiction.cooling_off(:qld) == %Jurisdiction.Policy{
             business_days: 5,
             forfeit_rate: Decimal.new("0.0025"),
             auction: :exempt
           }
  end

  test "New South Wales requires the contract, title search, drainage diagram and planning certificate" do
    assert Jurisdiction.required_documents(:nsw) == [
             :contract,
             :title_search,
             :drainage_diagram,
             :planning_certificate
           ]
  end

  test "Victoria requires the vendor statement, statement of information and title search" do
    assert Jurisdiction.required_documents(:vic) == [
             :vendor_statement,
             :statement_of_information,
             :title_search
           ]
  end

  test "Queensland requires the form 6, seller disclosure and title search" do
    assert Jurisdiction.required_documents(:qld) == [
             :form_6,
             :seller_disclosure,
             :title_search
           ]
  end
end
