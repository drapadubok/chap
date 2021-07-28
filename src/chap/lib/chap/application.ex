defmodule Chap.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      ChapWeb.Telemetry,
      ChapWeb.Endpoint,
      Chap.ClickhouseRepo,
      Chap.Cache
    ]

    opts = [strategy: :one_for_one, name: Chap.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    ChapWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
