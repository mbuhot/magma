defmodule Mix.Tasks.Magma.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  defp install(argv \\ []) do
    test_project()
    |> Igniter.compose_task("magma.install", argv ++ ["--yes"])
  end

  test "writes the four resources into a domain of the application's own" do
    igniter = install()

    for file <- ~w[workflow checkpoint signal waiter] do
      assert_creates(igniter, "lib/test/magma/#{file}.ex")
    end

    assert_creates(igniter, "lib/test/magma.ex")
  end

  test "each resource carries the extension for the role it plays" do
    igniter = install()

    assert source_for(igniter, "lib/test/magma/workflow.ex") =~ "Magma.Resource.Workflow"
    assert source_for(igniter, "lib/test/magma/checkpoint.ex") =~ "Magma.Resource.Checkpoint"
    assert source_for(igniter, "lib/test/magma/signal.ex") =~ "Magma.Resource.Signal"
    assert source_for(igniter, "lib/test/magma/waiter.ex") =~ "Magma.Resource.Waiter"
  end

  test "the dependent resources name the workflow resource, and the workflow does not" do
    igniter = install()

    for file <- ~w[checkpoint signal waiter] do
      source = source_for(igniter, "lib/test/magma/#{file}.ex")

      assert source =~ "magma do"
      assert source =~ "Test.Magma.Workflow"
    end

    refute source_for(igniter, "lib/test/magma/workflow.ex") =~ "magma do"
  end

  test "each resource gets its own table" do
    igniter = install()

    assert source_for(igniter, "lib/test/magma/workflow.ex") =~ "magma_workflows"
    assert source_for(igniter, "lib/test/magma/checkpoint.ex") =~ "magma_checkpoints"
    assert source_for(igniter, "lib/test/magma/signal.ex") =~ "magma_signals"
    assert source_for(igniter, "lib/test/magma/waiter.ex") =~ "magma_waiters"
  end

  test "magma is pointed at the domain and the repo it should use" do
    igniter = install()

    config = source_for(igniter, "config/config.exs")

    assert config =~ "config :magma"
    assert config =~ "domain: Test.Magma"
    assert config =~ "repo: Test.Repo"
  end

  test "a named domain is used instead of the default" do
    igniter = install(["--domain", "Test.Workflows"])

    assert_creates(igniter, "lib/test/workflows/workflow.ex")
    assert source_for(igniter, "lib/test/workflows/workflow.ex") =~ "domain: Test.Workflows"
  end

  test "running it a second time changes nothing" do
    first = install() |> apply_igniter!()

    second = Igniter.compose_task(first, "magma.install", ["--yes"])

    assert_unchanged(second)
  end

  defp source_for(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end
end
