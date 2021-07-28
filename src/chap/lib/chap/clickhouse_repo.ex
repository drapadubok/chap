defmodule Chap.ClickhouseRepo do
  use Ecto.Repo,
      otp_app: :chap,
      adapter: ClickhouseEcto

  defmacro __using__(_) do
    quote do
      alias Chap.ClickhouseRepo
      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]
    end
  end
end
