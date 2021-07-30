# A learning experience with Clickhouse and Elixir.

So what is this repo about? 

My plan was to have a hobby project on a couple of technologies that I am curious about, because I haven't had a chance to work on something hands-on for a little while.

This is going to be a backend for a "funnel analytics" tool. It's quoted, because it's so much more than what I'm going to have here, but it's a start. What do you do with a funnel? Imagine you have an event pipeline. It can be a sequence of steps between impression and acquisition, or maybe it's a series of quests a player does. If you take a large set of users, not everyone will reach the final step. What you want to find out is, as exploratory step, where is a bottleneck. And based on that, you would want to proceed with experimentation (AB test, for example) to find a way to make more users go to further steps of the funnel.

While in general it's important to have a proper hypothesis BEFORE the experiment, and base the decision on a metric that you picked before the experiment, there is a value in an ability to explore the data, and having a simple dynamic funnel tool can help with that. Here I'm going to make a very simplistic tool, more to play with the tech, and hopefully it will inspire you to do something fun too.

Before I begin, I have to definitely mention [Plausible](https://github.com/plausible/analytics) here, because as I was working through some of the difficulties with Clickhouse - Elixir interfacing, I found solutions in their codebase. They are building a lightweight, privacy-friendly analytics solution, which looks clear and simple. My choice of mixing Clickhouse with Elixir was parallel, not inspired by Plausible. Regardless, these people are awesome, so follow them!

### Clickhouse

Clickhouse is an OLAP database which was originally open-sourced by Yandex. It powers Yandex.Metrica and is specifically geared towards handling massive scale web analytics workloads. There are some amazing benchmarks of it done by [Mark Litwintschik](https://tech.marksblogg.com/benchmarks.html), and it's definitely a very powerful tool. 

However, one additional reason why I picked it (and how I actually learned about it) is that it has some abstractions for fairly common, yet sometimes challenging analytic operations. At some point in my career, I was building a tool for funnel analytics, which was supposed to provide some kind of Mixpanel-like experience based on event store in AWS Redshift. It took a while to make it work well with the architecture we used to have, and performance was not stellar.

So here I'm trying to take advantage of some of the analytic functions provided by Clickhouse, and make a tiny example of how such funnel tool would have looked like. 

### Phoenix

Phoenix is a web framework written in Elixir. I've been touching it a bit in the last few years, because I was curious about Elixir as a language. A lot of Python code I've been writing in the past few years is essentially reimplementing certain patterns of parallelization of workloads which are absolutely fluent and simple in Elixir.

However, Elixir is challenging for me, due to the syntax and some of the idioms that I struggle with, so even though this specific example doesn't take advantage of any of the Elixir strengths, I used it to get a bit more familiar with the language.

## The setup
Here I have four components that need to be taken care of.
* Kubernetes - this is where this solution will run. I'll be using minikube here.
* Zookeeper installation - this is required for replication, and at some point I wanted to simulate a real-time solution by having a Kafka stream feeding the database. I didn't have time for that, so here ZK is only for replication.
* Clickhouse installation - I'll be using Clickhouse Operator, developed and maintained by Altinity, a company that offers managed Clickhouse solutions.
* Phoenix JSON API - this is how I will be interacting with the Clickhouse installation. 
* (TODO) Web UI - an interface to allow easier visualization of the results.
* (TODO) Prometheus monitoring - didn't have time to set this up, however should be fairly easy, a lot of documentation available. 

### Kubernetes
I will need to have a functional minikube installation, see [Minikube docs](https://minikube.sigs.k8s.io/docs/start/) to get started.
This setup essentially required two commands:
1) `minikube start` - to actually create and start the cluster.
2) `minikube tunnel` - to allow us to talk with the load balancer service deployed to the cluster (I am running locally here, so this is needed to be able to reach it). You can just run this command in a terminal window, and it will automatically pick up if a load balancer service is created.

### Zookeeper
I have relied on two documents for this setup:
[k8s Zookeeper guide](https://kubernetes.io/docs/tutorials/stateful-application/zookeeper/) and [CH Zookeeper guide](https://github.com/Altinity/clickhouse-operator/blob/master/docs/zookeeper_setup.md).

All the resources were deployed using a [manifest](infra/zookeeper/zookeeper.yaml). The meaning of each line is described in detail in the k8s ZK guide linked above. The only peculiarity here is a commented node affinity section - this forces the pods to be created on different nodes to ensure availability, and since I have only one node - I need to disable it, or the pods will stay forever in Pending state.

1) `kubectl apply -f zookeeper/zookeeper.yaml` to deploy.
2) `kubectl get pods -n zk` to check that the pods are created.

### Clickhouse
First of all, I deployed the Clickhouse Operator - it takes care of most of the deployment details and makes configuration a breeze.

Let's look at it in more detail, since I took a fairly simple approach, without configuring much.
1) `./ch/ch-install.sh` - run this to deploy the operator. You have to specify the namespace, and it's important, because Operator will be observing only that namespace. I hardcoded it to be `OPERATOR_NAMESPACE=ch`, as you can see in the [script](infra/clickhouse/ch-install.sh).
2) `kubectl apply -f ch/installation.yaml -n ch`. Once it's installed, you can create the actual installation. See the [manifest](infra/clickhouse/installation.yaml) for details. Most of the things are self-explanatory, but I'll still walk through them.
    * PodTemplate specifies the docker image to be used. I picked the later version, because I thought I would need some of the functionalities that were added there. I didn't, but this is how you can change the version of CH.
    * I opted to create a cluster with 2 shards, and 2 replicas per each. There is a wonderful issue on github that gives more suggestions on the replication and sharding setup: https://github.com/ClickHouse/ClickHouse/issues/2161. 
    * I noticed that logs are very verbose, so adjusted the logging level to `information`.
    * I also realized that the default user created with the Operator can only access CH from within the cluster. To deal with that, I created another user that can access it from any network. The details on this can be found here: https://github.com/Altinity/clickhouse-operator/issues/265
3) `kubectl get pods -n ch` - verify that the pods are created with no errors.

### Intermediate check-up
At this point I should have all the underlying infra set up. 

I will create a deployment of Phoenix later on, once I walk through the implementation details.

Let's first verify that Clickhouse can be used, by launching a client on one of the pods. You need to take note of one of the pods, and run the following command (chi-repl-05-replicated-0-0-0 is my pod name):
    
`kubectl -n ch exec -it chi-repl-05-replicated-0-0-0 -- clickhouse-client`

You should see a REPL where you can pass queries. Let's run some queries!
        
* Do a `SELECT 1` for fun!
* Verify it's distributed (you should see both shards):        
    ```
    CREATE TABLE test_distr AS system.one ENGINE = Distributed('{cluster}', system, one);
    ```
    ```
    select hostName() from test_distr;
    ``` 
* Check what storage you have:
    ```
    SELECT
        name,
        path,
        formatReadableSize(free_space) AS free,
        formatReadableSize(total_space) AS total,
        formatReadableSize(keep_free_space) AS reserved
    FROM system.disks
    ```

### Producing sample data
To create funnels I need some events. Here is how I'm going to do that. This part depends on Python, so you might want to install the [requirements](scripts/requirements.txt).

#### [Create the tables](scripts/create_tables.py) by running `python scripts/create_tables.py`. 
I will create two tables, and this is something that I found to be a bit less intuitive with Clickhouse. The tables serve as abstractions to various functionalities (e.g. a table can serve as an interface for Kafka, or as an abstraction that distributes the queries across shards). Here is a list, and it's quite exciting what some of the table engines can do: [Table Engines](https://clickhouse.tech/docs/en/engines/table-engines/).

First, I create a replicated table on a cluster, meaning that I'll have a local replica of this table on each node.


    CREATE TABLE IF NOT EXISTS events_local on cluster '{cluster}' 
    (
        ts DateTime64(6), 
        variant String, 
        event_name String, 
        uid Int32
    ) engine=ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{shard}/{database}/{table}', '{replica}') 
    PARTITION BY toYYYYMM(ts) 
    ORDER BY (ts);

At this point we can learn a bit more about Zookeeper. Since it takes care of the replication, it should have some information for us. I didn't need it, but I find it useful to know what can I find under the hood, so here is a command. You run it on one of the Zookeeper nodes to list the keys at a certain path:
`kubectl exec -n zk zookeeper-1 zkCli.sh ls /clickhouse`. Feel free to explore further.

Now that I have the local tables, I can create another table on top of them which will take care of the distribution of data, to allow us querying data locally on each of the nodes, and combining it later into a single response.

    CREATE TABLE IF NOT EXISTS events on cluster '{cluster}' AS events_local 
    ENGINE = Distributed('{cluster}', default, events_local, rand());
    
One thing to know, basic `DROP TABLE` queries are not enough at this point, you'll need to add `ON CLUSTER`, e.g. 

    DROP TABLE IF EXISTS default.events ON CLUSTER '{cluster}';
    DROP TABLE IF EXISTS default.events_local ON CLUSTER '{cluster}';

#### [Produce a sample](scripts/create_data.py). This might need a bit of explanation.
Here I'm using a simplistic config to simulate two groups, A and B, and I provide a distribution for sampling and parameters for this distribution to simulate some kind of experiment.
The key here is in this dict:


    {
       "event_name": "go_to_checkout",
       "distribution": np.random.binomial,
       "params": {
           "A": {"p": 0.1, "n": 1},
           "B": {"p": 0.5, "n": 1}
       }
    }

As you can see, the parameter for group B is a lot higher, so I simulate that for group B, the probability for event `go_to_checkout` to happen is a lot higher.

Once this script finishes running, it will insert the data to Clickhouse `default.events` table. The events will look like this:
```json
{"ts": "2021-07-22 15:24:28.924616", "event_name": "go_to_checkout", "uid": 23, "variant": "A"}
```

Verify that by running a query:

    SELECT event_name, count() FROM events GROUP BY event_name

### Elixir and Phoenix
At this point I should have a cluster, data loaded, and everything ready for the funnel tool to be built. Now, I don't want to build a UI at this point, so all I'm delivering is a JSON API that can be interfaced with.

At this point I assume that you have Elixir and Phoenix of version >= 1.5 installed (I've got 1.5.9).

1) `mix phx.new chap --no-webpack --no-html --no-ecto` - create bare bones Phoenix app. I don't need webpack or html, because I'm not having a UI here, and I also opt out of Ecto (ORM that is used by Phoenix). I will however use Ecto (clickhouse_ecto package), but I want this to be minimal and avoid the boilerplate created.
2) Verify that it works: `mix phx.server` should run successfully.

    Now I need to add dependency to be able to talk to Clickhouse, and I have a trouble. The https://github.com/clickhouse-elixir/clickhouse_ecto which I want to use has an issue with the Clickhouse version that I have deployed. 
    
    I have mentioned it here: https://github.com/clickhouse-elixir/clickhousex/issues/42 , but fortunately I don't have to wait for it to be fixed! The folks at Plausible found a consistent way of dealing with the issue (using Hackney to construct headers, instead of writing them out explicitly in a problematic way), and I can add the dependency like this to my `mix.exs`: `{:clickhouse_ecto, git: "https://github.com/plausible/clickhouse_ecto.git"}`

3) Add config for Clickhouse-Ecto to [config](src/chap/config/dev.exs). As you can see, it includes secrets, that should otherwise be passed as environment variables. I also set `show_sensitive_data_on_connection_error` to true, to be able to debug queries. 
    ```
        config :chap, Chap.ClickhouseRepo,
          show_sensitive_data_on_connection_error: true,
          adapter: ClickhouseEcto,
          loggers: [Ecto.LogEntry],
          hostname: "localhost",
          port: 8123,
          database: "default",
          username: "dima",
          password: "secret",
          timeout: 60_000,
          ownership_timeout: 60_000,
          pool_size: 30
    ```
   I will be deploying this, so I'm also preparing a production config. I prefer to parametrize it with environment variables, so I'm using [runtime config](src/chap/config/runtime.exs) to parametrize. These will not be baked into the release, and will be possible to provide when I start the binary.

4) I need to create the Ecto repo, which will take care of interfacing with the database. Here is the [implementation](src/chap/lib/chap/clickhouse_repo.ex). I also need to add it to my [application supervision tree](src/chap/lib/chap/application.ex), in the children section.
5) I also want to reduce the time spent on waiting for the results that I've already have computed, so an [ETS cache](src/chap/lib/chap/cache.ex) is introduced. It has to also be added to the supervision tree. You can find a valuable discussion on where in the supervision tree should ETS live [here](https://elixirforum.com/t/do-we-need-a-process-for-ets-tables/22705/4).
6) I'll have a controller ready to accept my requests. I have added a [funnel controller](src/chap/lib/chap_web/controllers/funnel_controller.ex) here, and exposed it in the [router](src/chap/lib/chap_web/router.ex). As you can see, I have two routes, one is GET and one is POST. The GET route has hardcoded parameters and it is how I was learning. The POST is the main endpoint that would be used by e.g. UI. You can also see the `IO.inspect` calls - I love to learn how my stuff works by printing everything.
7) Finally, a [health controller](src/chap/lib/chap_web/controllers/health_controller.ex) to provide endpoints for k8s liveness and readiness probes.  

To deploy Phoenix app I'll be using a [Dockerfile](src/chap/Dockerfile) and a [manifest](infra/chap/installation.yaml). Here I hardcode some secrets, but normally I would be creating secret values and secrets in k8s cluster via Terraform, to avoid putting them into code at all. 

At this point I have everything, except the actual funnel implementation. In the next section let me walk through it step by step.

### Funnel implementation
The code is [here](src/chap/lib/chap/funnel.ex). I will walk through each section of the file. First I show the code section, and below is the comment.

```elixir
defmodule Chap.Funnel do
  require Logger

  @derive Jason.Encoder
  @enforce_keys [:breakdown_fields, :ordered_event_list]
  defstruct [:breakdown_fields, :ordered_event_list, uid_column: "uid", timestamp_column: "ts", window: 3600]
```

Here I specify a struct to keep the parameters needed to reproduce the funnel. I will be using a hashed stringified version of this struct as a key in the cache.

```elixir
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
```

Here I define a few fragments of the query, specifically, the breakdown section (used in GROUP BY) and events list section (used in the Clickhouse windowFunnel function, which I'll show in a moment).

```elixir

  @doc """
  Hash the funnel config to store in the ETS cache.
  """
  def hash_config(funnel_config) do
    funnel_config
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
```

I hash the config by using Erlang phash2 function, and then I also define a function that I will use to store the funnel config and query result in the cache.

```elixir
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
```

Clickhouse has a few [parametric aggregate functions](https://clickhouse.tech/docs/en/sql-reference/aggregate-functions/parametric-functions/), of which the windowFunnel will be the highlight today.

Here I will take the list of events and breakdowns received in a POST request, and construct a query that will check, how many unique users reached a certain step (or level) in the funnel.

An example query (you can run it against the cluster directly) would look like this, and the query formatting code here aims at making this flexible:

      SELECT level, variant, count() as cnt
      FROM (
          SELECT
              uid,
              variant,
              windowFunnel(3600)(
                  toDateTime(ts),
                  event_name = 'visit', event_name = 'add_to_cart', event_name = 'open_cart', event_name = 'go_to_checkout', event_name = 'purchase'
              ) as level
          FROM events
          GROUP BY uid, variant
      )
      GROUP BY level, variant
      ORDER BY level ASC 

```elixir
  @doc """
  Construct cumulative funnel from the CH funnel version.
  CH funnel shows the count of unique users at each level of the funnel.
  The total number of users at each step is the sum of all levels >= to the current level.

    ## Example

      iex> Chap.Funnel.cumulative_funnel([
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
```

There is one detail here, which is the way funnel is displayed in e.g. Mixpanel, versus what you can see here.

In Mixpanel, each subsequent level of the funnel has the total number of users that reached this or more levels. 
Clickhouse windowFunnel instead returns a total number of users that stopped at this level.

For example, if I have 10 users visit, 6 out of them add to cart, 2 out of them checkout, and 1 purchased:

Clickhouse: 4, 4, 1, 1. The total is 10, out of which 4 only visited, 4 only visited and added to cart, one only visited, added to cart and went to checkout, and one went all the way to purchase.

Mixpanel: 10, 6, 2, 1. So 10 visited, of them 6 added to cart, of them only 2 went to checkout, and one purchased.
 
This section formats the data in a way similar to Mixpanel.

```elixir
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
```

This final section puts everything together, and it is what I use in the [controller](src/chap/lib/chap_web/controllers/funnel_controller.ex).

### Verifying that it works
I didn't write any tests, sorry! So let's just curl this a little bit:

```json

curl -X POST "http://localhost:4000/api/funnel" -H  "accept: application/json" -H  "Content-Type: application/json" -d '{"event_list":["visit","go_to_checkout","purchase"],"breakdowns":["variant"]}'
{"data":{"cached":false,"funnel_config":{"breakdown_fields":["variant"],"ordered_event_list":["visit","go_to_checkout","purchase"],"timestamp_column":"ts","uid_column":"uid","window":3600},"query_result":[{"A":[{"count":400003,"level":1},{"count":6422,"level":2},{"count":689,"level":3}]},{"B":[{"count":399617,"level":1},{"count":32070,"level":2},{"count":3217,"level":3}]}]},"status":"ok"}

curl -X POST "http://localhost:4000/api/funnel" -H  "accept: application/json" -H  "Content-Type: application/json" -d '{"event_list":["visit","purchase"],"breakdowns":["variant"]}'
{"data":{"cached":false,"funnel_config":{"breakdown_fields":["variant"],"ordered_event_list":["visit","purchase"],"timestamp_column":"ts","uid_column":"uid","window":3600},"query_result":[{"A":[{"count":400003,"level":1},{"count":689,"level":2}]},{"B":[{"count":399617,"level":1},{"count":3217,"level":2}]}]},"status":"ok"}

curl -X POST "http://localhost:4000/api/funnel" -H  "accept: application/json" -H  "Content-Type: application/json" -d '{"event_list":["visit","purchase"],"breakdowns":["variant"]}'
{"data":{"cached":true,"funnel_config":{"breakdown_fields":["variant"],"ordered_event_list":["visit","purchase"],"timestamp_column":"ts","uid_column":"uid","window":3600},"query_result":[{"A":[{"count":400003,"level":1},{"count":689,"level":2}]},{"B":[{"count":399617,"level":1},{"count":3217,"level":2}]}]},"status":"ok"}
```

## Conclusion
I've had this hobby project idea in my TODO list for about 3 years now, and only now I've managed to fulfill it. It felt awesome to code something that I was genuinely interested in, without having to think about it as a "deliverable". 

In practice, Clickhouse feels like a great tool with a massive amount of optimizations and configurations available, which makes it stand out (perhaps not always in a better way, depending on how you look at it) compared to solutions like Snowflake, BigQuery or Redshift, where most of the things just work without much need for configuration. However, as benchmarks show, Clickhouse can blow them out of the water if done properly, and let's be fair, there is a lot of engineering fun working with a tool like this. I hope that it stays actively developed and we'll see more examples of how to set it up for production with a reasonable set of conventions, avoiding the necessity to dive deeper into configuration until it's really crucial.

As for this repo, yes, there are no unit tests, and yes, the tech choices may or may not be the best for the job, but who cares? I was having fun, I've learned a few things about k8s, Zookeeper, Clickhouse and Elixir as I was preparing this repo, and I've reminded myself about why this profession attracted me in the first place.

I don't like TED talks in general, but there was a gem, told by [Simone Giertz](https://www.youtube.com/c/simonegiertz/videos), who is well known for her passion of building useless robots: https://www.ted.com/talks/simone_giertz_why_you_should_make_useless_things

There is a great value (sometimes it's just personal, for me) in making things, and if this repo doesn't solve any of your problems - too bad, but maybe it will make you feel better about building something just for the fun of it.
