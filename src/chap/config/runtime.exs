import Config

if config_env() == :prod do
  config :chap, ChapWeb.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    http: [
      port: String.to_integer(System.fetch_env!("PORT") || "4000"),
      transport_options: [socket_opts: [:inet6]]
    ],
    url: [host: System.fetch_env!("HOST"), port: String.to_integer(System.fetch_env!("PORT") || "4000")]

  config :chap, Chap.ClickhouseRepo,
    hostname: System.fetch_env!("DB_HOSTNAME"),
    port: 8123,
    database: System.fetch_env!("DB_NAME"),
    username: System.fetch_env!("DB_USERNAME"),
    password: System.fetch_env!("DB_PASSWORD")
end
