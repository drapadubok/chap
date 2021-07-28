defmodule Chap.Cache do
  use GenServer
  @table :funnel_cache

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :ets.new(@table, [:set, :protected, :named_table])
    {:ok, %{}}
  end

  def set(key, val) do
    GenServer.call(__MODULE__, {:set, key, val})
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:reply, value, state}
      [] -> {:reply, :not_found, state}
    end
  end

  def handle_call({:set, key, val}, _from, state) do
    # insert the value into the table
    case :ets.insert(@table, {key, val}) do
      true -> {:reply, val, state}
      _ -> {:reply, :error, state}
    end
  end
end
