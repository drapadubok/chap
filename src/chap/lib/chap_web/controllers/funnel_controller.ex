defmodule ChapWeb.FunnelController do
  use ChapWeb, :controller
  use Chap.ClickhouseRepo
  use Plug.ErrorHandler

  def test_funnel(conn, params) do
    IO.inspect(conn)
    IO.inspect(params)
    {:ok, funnel_result} = Chap.Funnel.calculate_funnel()
    json(conn, %{
      status: :ok,
      data: funnel_result
    })
  end

  def compute_funnel(conn, params) do
    IO.inspect(conn)
    IO.inspect(params)
    {:ok, funnel_result} = Chap.Funnel.calculate_funnel(params)
    json(conn, %{
      status: :ok,
      data: funnel_result
    })
  end
end
