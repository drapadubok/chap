defmodule Chap.Funnel do
  require Logger

  @derive Jason.Encoder
  @enforce_keys [:breakdown_fields, :ordered_event_list]
  defstruct [:breakdown_fields, :ordered_event_list, uid_column: "uid", timestamp_column: "ts", window: 3600]

  defp event_query_string(event_name), do: "event_name = '#{event_name}'"

  defp construct_event_list(%{ordered_event_list: ordered_event_list}) do
    event_query =
      ordered_event_list
      |> Enum.map_join(", ", &event_query_string/1)
    {:ok, event_query}
  end

  defp construct_breakdown_list(%{breakdown_fields: breakdown_fields}) do
    breakdown_query =
      breakdown_fields
      |> Enum.join(", ")
    {:ok, breakdown_query}
  end

  @doc """
  Serialize the funnel config into a deterministic string to calculate the hash.
  """
  def serialize(funnel_config) do
    """
        #{funnel_config.breakdown_fields}-
        #{funnel_config.ordered_event_list}-
        #{funnel_config.uid_column}-
        #{funnel_config.timestamp_column}-
        #{funnel_config.window}
    """
  end

  @doc """
  Hash the funnel config to store in the ETS cache.
  """
  def hash_config(funnel_config) do
    funnel_config
    |> serialize
    |> :erlang.phash2
  end

  @doc """
  Cache funnel config and result in the ETS cache.
  """
  def cache_config(funnel_config, query_result) do
    funnel_config
    |> hash_config
    |> Chap.Cache.set(%{funnel_config: funnel_config, query_result: query_result})
    :ok
  end

  @doc """
  Construct a windowed funnel query.
  """
  def window_funnel_query(
    %__MODULE__{} = funnel_config
  ) do
    with {:ok, event_query} <- construct_event_list(funnel_config),
         {:ok, breakdown_query} <- construct_breakdown_list(funnel_config)
      do
      funnel_query = "
      SELECT level, #{breakdown_query}, count() as cnt
      FROM (
          SELECT
              #{funnel_config.uid_column},
              #{breakdown_query},
              windowFunnel(#{funnel_config.window})(
                  toDateTime(#{funnel_config.timestamp_column}),
                  #{event_query}
              ) as level
          FROM events
          GROUP BY #{funnel_config.uid_column}, #{breakdown_query}
      )
      GROUP BY level, #{breakdown_query}
      ORDER BY level ASC
      "
      {:ok, funnel_query}
    else
      err -> IO.puts(err)
    end
  end

  @doc """
  Construct cumulative funnel from the CH funnel version.
  CH funnel shows the count of unique users at each level of the funnel.
  The total number of users at each step is actually the sum of all levels >= to the current level.

    ## Example

      iex> Main.cumulative_funnel([
        [1, "B", 319594],
        [1, "A", 320226],
        [2, "A", 15817],
        [2, "B", 15878],
        [3, "B", 32075],
        [3, "A", 57538],
        [4, "B", 28853],
        [4, "A", 5733],
        [5, "A", 689],
        [5, "B", 3217]
      ])
      [
        {"A", [[1, 400003], [2, 79777], [3, 63960], [4, 6422], [5, 689]]},
        {"B", [[1, 399617], [2, 80023], [3, 64145], [4, 32070], [5, 3217]]}
      ]
  """
  def cumulative_funnel_by_variant({v, funnel_rows}) do
    funnel_by_variant = funnel_rows
    |> Enum.map(fn [level, _variant, count] -> [level, count]  end)  # drop variant (redundant after groupby)
    |> Enum.reverse
    |> Enum.scan(fn [level_this, cnt_this], [_level_next, cnt_next] -> [level_this, cnt_this + cnt_next] end)  # summarize steps
    |> Enum.map(fn [level, count] -> %{level: level, count: count} end)
    %{v => funnel_by_variant}
  end

  def cumulative_funnel(funnel_rows) do
    funnel_rows
    |> Enum.group_by(fn [_, variant, _] -> variant end)  # group by variant
    |> Enum.map(&cumulative_funnel_by_variant/1)
  end

  def calculate_funnel(opts \\ %{
    "event_list" => ["visit", "add_to_cart", "open_cart", "go_to_checkout", "purchase"],
    "breakdowns" => ["variant"]
  }) do
    %{"breakdowns" => breakdowns, "event_list" => event_list} = opts
    funnel_config = %Chap.Funnel{breakdown_fields: breakdowns, ordered_event_list: event_list}

    # Check if this config was received earlier
    cached_funnel_result = funnel_config
    |> Chap.Funnel.hash_config
    |> Chap.Cache.get

    case cached_funnel_result do
      :not_found ->
        Logger.info("Not found in cache, computing")
        {:ok, funnel_query} = Chap.Funnel.window_funnel_query(funnel_config)
        Logger.info(funnel_query)

        response = Ecto.Adapters.SQL.query!(Chap.ClickhouseRepo, funnel_query)
        Logger.info(response)

        computed_funnel_result = cumulative_funnel(response.rows)
        :ok = Chap.Funnel.cache_config(funnel_config, computed_funnel_result)
        Logger.info("Funnel computed and cached.")

        funnel_result = %{funnel_config: funnel_config, query_result: computed_funnel_result, cached: false}
        {:ok, funnel_result}
      _ ->
        funnel_result = Map.put(cached_funnel_result, :cached, true)
        {:ok, funnel_result}
    end
  end
end
