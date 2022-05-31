defmodule StoreTest do
  use ExUnit.Case, async: true

  alias Eiger.Cache.Store

  setup do
    %{store: Store.init(:test)}
  end

  test "#init", %{store: store} do
    assert store == :test
  end

  test "#store", %{store: store} do
    {key, value, expiration} = Store.store(store, :t1, 10, 10_000)
    assert key == :t1
    assert value == 10
    assert expiration >= :os.system_time(:millisecond) + 9999
  end

  describe "#get" do
    test "non-existing", %{store: store} do
      assert Store.get(store, :nope) == :error
    end

    test "cache expired", %{store: store} do
      Store.store(store, :expired, 10, 100)
      :timer.sleep(200)

      assert Store.get(store, :expired) == :error
    end

    test "cache still valid", %{store: store} do
      Store.store(store, :valid, 10, 10_000)

      assert Store.get(store, :valid) == {:ok, 10}
    end
  end
end
