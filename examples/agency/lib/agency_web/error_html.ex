defmodule AgencyWeb.ErrorHTML do
  @moduledoc false

  use AgencyWeb, :html

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
