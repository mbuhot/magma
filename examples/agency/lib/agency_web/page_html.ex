defmodule AgencyWeb.PageHTML do
  @moduledoc false

  use AgencyWeb, :html

  def home(assigns) do
    ~H"""
    <p>Agency</p>
    """
  end
end
