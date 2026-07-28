defmodule Magma.StoreTest do
  use ExUnit.Case, async: true

  alias Magma.Store
  alias Magma.Test.Store, as: TestStore

  test "finds the resource playing each role in the configured domain" do
    assert Store.resource(:workflow) == TestStore.Workflow
    assert Store.resource(:checkpoint) == TestStore.Checkpoint
    assert Store.resource(:signal) == TestStore.Signal
    assert Store.resource(:waiter) == TestStore.Waiter
  end

  test "names the role and the domain when nothing plays it" do
    defmodule EmptyDomain do
      @moduledoc false
      use Ash.Domain, validate_config_inclusion?: false

      resources do
      end
    end

    error = assert_raise RuntimeError, fn -> Store.resource(:workflow, EmptyDomain) end
    message = error.message

    assert message =~ "workflow"
    assert message =~ inspect(EmptyDomain)
    assert message =~ "Magma.Resource.Workflow"
  end

  test "reports the repo the store writes through" do
    assert Store.repo() == Magma.TestRepo
  end
end
