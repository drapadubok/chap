defmodule ChapWeb.HealthController do
  use ChapWeb, :controller
  use Chap.ClickhouseRepo
  use Plug.ErrorHandler

  def alive(conn, params) do
    IO.inspect(conn)
    IO.inspect(params)
    json(conn, %{status: :ok})
  end

  def ready(conn, params) do
    IO.inspect(conn)
    IO.inspect(params)
    response = Ecto.Adapters.SQL.query!(Chap.ClickhouseRepo, "SELECT 1")
    IO.inspect(response)
    json(conn, %{status: :ok})
  end
end
