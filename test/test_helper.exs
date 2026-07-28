# Integration tests run against a real PostgreSQL server. Connection
# settings follow the libpq environment variables so CI (service
# container with a password) and local development (trust auth) both
# work without configuration changes.
Application.put_env(:localize_ecto, Localize.Ecto.TestRepo,
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  username: System.get_env("PGUSER", System.get_env("USER")),
  password: System.get_env("PGPASSWORD"),
  database: "localize_ecto_test",
  pool_size: 2,
  log: false
)

repo_config = Application.get_env(:localize_ecto, Localize.Ecto.TestRepo)

case Ecto.Adapters.Postgres.storage_up(repo_config) do
  :ok -> :ok
  {:error, :already_up} -> :ok
  {:error, reason} -> raise "could not create test database: #{inspect(reason)}"
end

{:ok, _} = Localize.Ecto.TestRepo.start_link()

# The SQLite suites need the localize_icu extension, which is an opt-in
# build (LOCALIZE_ECTO_SQLITE_ICU=true). Tagged tests are excluded
# unless it is present, so the default `mix test` stays pure Elixir.
sqlite_icu? = Localize.Ecto.SQLite3.Extension.available?()

if sqlite_icu? do
  sqlite_database = Path.join(System.tmp_dir!(), "localize_ecto_test.sqlite3")

  # A single connection in WAL mode: several pooled connections racing
  # to create the same new database file lock each other out.
  Application.put_env(:localize_ecto, Localize.Ecto.SQLiteTestRepo,
    database: sqlite_database,
    load_extensions: Localize.Ecto.SQLite3.Extension.load_extensions(),
    journal_mode: :wal,
    busy_timeout: 5_000,
    pool_size: 1,
    log: false
  )

  for suffix <- ["", "-wal", "-shm"], do: File.rm(sqlite_database <> suffix)

  {:ok, _} = Localize.Ecto.SQLiteTestRepo.start_link()
end

ExUnit.start(exclude: if(sqlite_icu?, do: [], else: [:sqlite_icu]))
