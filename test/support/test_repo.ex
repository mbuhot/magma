defmodule Magma.TestRepo do
  @moduledoc "The Postgres repo the test suite runs magma's resources against."

  use AshPostgres.Repo, otp_app: :magma

  @impl true
  def installed_extensions, do: ["ash-functions"]

  @impl true
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
end
