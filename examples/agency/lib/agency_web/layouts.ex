defmodule AgencyWeb.Layouts do
  @moduledoc "The application's chrome: the document shell."

  use AgencyWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Agency</title>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
