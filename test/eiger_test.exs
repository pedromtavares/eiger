defmodule EigerTest do
  use ExUnit.Case

  describe "#register_function" do
    test "returns :ok" do
      assert Eiger.register_function(fn -> {:ok, 50} end, :register_works, 500, 300) == :ok
    end

    test "returns :already_registered" do
      Eiger.register_function(fn -> {:ok, 50} end, :already_registered, 500, 300)
      wait_for_completion()

      assert Eiger.register_function(fn -> {:ok, 50} end, :already_registered, 500, 300) ==
               {:error, :already_registered}
    end

    test "properly refreshes at an interval" do
      Eiger.register_function(fn -> {:ok, :os.system_time(:second)} end, :refresh, 2000, 1000)
      wait_for_completion()
      {:ok, old_time} = Eiger.get(:refresh)

      # Wait a bit over the refresh interval to give time for the function to refresh the stored data
      :timer.sleep(1100)
      {:ok, new_time} = Eiger.get(:refresh)

      assert new_time > old_time
    end
  end

  describe "#get" do
    test "existing value" do
      Eiger.register_function(fn -> {:ok, 30} end, :get_exists, 5000, 3000)
      wait_for_completion()

      assert Eiger.get(:get_exists) == {:ok, 30}
    end

    test "non-existing value" do
      assert Eiger.get(:non_existing) == {:error, :not_registered}
    end

    test "non-existing value, computation in progress, waits" do
      Eiger.register_function(
        fn ->
          :timer.sleep(500)
          {:ok, 50}
        end,
        :computation_in_progress,
        2000,
        1000
      )

      wait_for_completion()
      assert Eiger.get(:computation_in_progress) == {:ok, 50}
    end

    test "non-existing value, computation in progress, times out" do
      Eiger.register_function(
        fn ->
          :timer.sleep(1000)
          {:ok, 55}
        end,
        :computation_timeout,
        5000,
        3000
      )

      wait_for_completion()
      assert Eiger.get(:computation_timeout, 200) == {:error, :timeout}
    end
  end

  # ------------------------------------------------

  defp wait_for_completion do
    pids = Task.Supervisor.children(Eiger.TaskSupervisor)
    Enum.each(pids, &Process.monitor/1)
    wait_for_pids(pids)
  end

  defp wait_for_pids([]), do: nil

  defp wait_for_pids(pids) do
    receive do
      {:DOWN, _ref, :process, pid, _reason} -> wait_for_pids(List.delete(pids, pid))
    end
  end
end
