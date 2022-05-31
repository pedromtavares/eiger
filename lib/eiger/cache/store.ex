defmodule Eiger.Cache.Store do
  @moduledoc """
  Wrapper module for our ETS cache store
  """

  @doc """
  Initializes an ETS table
  """
  @spec init(name :: atom()) :: atom()
  def init(name) do
    :ets.new(name, [:set, :protected, :named_table])
    name
  end

  @doc """
  Inserts calculated value along with its ttl, setting an expiration
  """
  @spec store(name :: atom(), key :: any(), value :: any(), ttl: non_neg_integer()) :: tuple()
  def store(name, key, value, ttl) do
    expiration = :os.system_time(:millisecond) + ttl
    data = {key, value, expiration}
    :ets.insert(name, data)
    data
  end

  @doc """
  Fetches a key from the ETS table, checking if it has expired
  """
  @spec get(name :: atom(), key :: any()) :: {:ok, any} | :error
  def get(name, key) do
    case :ets.lookup(name, key) do
      [result | _] -> check_expiration(result)
      [] -> :error
    end
  end

  # Returns a valid value only if its expiration is greater than current time
  @spec check_expiration(tuple) :: {:ok, any()} | :error
  defp check_expiration({_, value, expiration}) do
    cond do
      expiration > :os.system_time(:millisecond) -> {:ok, value}
      true -> :error
    end
  end
end
