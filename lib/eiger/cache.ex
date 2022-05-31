defmodule Eiger.Cache do
  @moduledoc """
  Server implementation of the cache
  """
  use GenServer

  alias Eiger.Cache.Store

  @type from() :: {pid(), tag :: term()}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{store: Store.init(:computations), tasks: %{}}}
  end

  @doc """
  Returns a cached value immediately if found, or blocks until a pending
  computation finishes processing and asychronously replies with a value
  """
  @impl GenServer
  def handle_call({:get_or_wait, key, timeout}, from, state) do
    get_or_wait(key, timeout, from, state)
  end

  @doc """
  Registers a computation by initiating the recompute infinite loop
  """
  @impl GenServer
  def handle_cast({:register, computation}, state) do
    send(self(), {:recompute, computation})

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:recompute, %{refresh_interval: refresh_interval} = computation}, state) do
    Process.send_after(self(), {:recompute, computation}, refresh_interval)

    {:noreply, start_computing(computation, state)}
  end

  @impl GenServer
  def handle_info({:get_or_wait, key, from, timeout}, state) do
    get_or_wait(key, timeout, from, state)
    {:noreply, state}
  end

  @doc """
  Callbacks that originate from Tasks, stores value in cache if successful or 
  prints the reason of failure
  """
  @impl GenServer
  def handle_info({ref, result}, %{store: store} = state) do
    # The task succeeded so we can cancel the monitoring and discard the DOWN message
    Process.demonitor(ref, [:flush])

    {{key, ttl}, state} = pop_in(state.tasks[ref])

    with {:ok, value} = result do
      Store.store(store, key, value, ttl)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, _, _, reason}, state) do
    {{key, _}, state} = pop_in(state.tasks[ref])
    IO.puts("Key #{inspect(key)} failed with reason #{inspect(reason)}")
    {:noreply, state}
  end

  # -----------------------------------------

  @spec computing?(any(), non_neg_integer(), from(), term()) :: :ok
  defp computing?(_key, timeout, from, _state) when timeout <= 0 do
    GenServer.reply(from, {:error, :timeout})
  end

  @spec computing?(any(), non_neg_integer(), from(), term()) :: tuple()
  defp computing?(key, timeout, from, %{tasks: tasks} = state) do
    if find_task(tasks, key) do
      Process.send_after(self(), {:get_or_wait, key, from, timeout - 100}, 100)
      {:noreply, state}
    else
      {
        :reply,
        {:error, :not_registered},
        state
      }
    end
  end

  @spec find_task(map(), any()) :: map() | nil
  defp find_task(tasks, key) do
    tasks
    |> Map.values()
    |> Enum.find(fn {task_key, _} -> task_key == key end)
  end

  @spec get_or_wait(any(), non_neg_integer(), from(), term()) :: tuple()
  defp get_or_wait(key, timeout, from, %{store: store} = state) do
    case Store.get(store, key) do
      :error -> computing?(key, timeout, from, state)
      {:ok, value} -> reply(value, from, state)
    end
  end

  @spec reply(any(), from(), term()) :: tuple()
  defp reply(value, from, state) do
    GenServer.reply(from, {:ok, value})
    {:reply, {:ok, value}, state}
  end

  @spec start_computing(%{key: any(), fun: fun(), ttl: non_neg_integer()}, term()) :: term()
  defp start_computing(%{key: key, fun: fun, ttl: ttl}, %{tasks: tasks} = state) do
    if find_task(tasks, key) do
      state
    else
      task = Task.Supervisor.async_nolink(Eiger.TaskSupervisor, fun)
      put_in(state.tasks[task.ref], {key, ttl})
    end
  end
end
