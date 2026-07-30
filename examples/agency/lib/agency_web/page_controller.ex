defmodule AgencyWeb.PageController do
  @moduledoc false

  use AgencyWeb, :controller

  def home(conn, _params), do: render(conn, :home)
end
