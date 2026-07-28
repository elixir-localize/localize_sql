defmodule Localize.Ecto.SQLite3.Extension do
  @moduledoc """
  Locates the `localize_icu` SQLite extension for loading into a connection.

  `localize_icu` is a SQLite loadable extension that registers ICU
  collations under the same names PostgreSQL uses — `de-x-icu`,
  `sv-x-icu`, `de-u-co-phonebk-x-icu` — along with ICU-backed
  two-argument `upper/2`, `lower/2` and `title/2` SQL functions. It is
  what makes `Localize.Ecto.SQLite3` work.

  Collations are registered on demand: the extension installs a
  `sqlite3_collation_needed` handler, so the first statement to name a
  collation SQLite does not have causes it to be built from the tag by
  ICU. Every tag ICU understands works, including the `-u-` tailorings
  that PostgreSQL needs a `CREATE COLLATION` for, and no migration is
  involved.

  ### Building the extension

  The extension needs a C compiler and the ICU development libraries, so
  it is not built unless asked for. Enable it with either:

      # config/config.exs — must be config.exs, it is read at compile time
      config :localize_ecto, :sqlite_icu, true

  or the `LOCALIZE_ECTO_SQLITE_ICU=true` environment variable when
  compiling. On macOS, `brew install icu4c`; on Debian and Ubuntu,
  `apt-get install libicu-dev`.

  ### Loading it

  Both `Exqlite` and `Ecto.Adapters.SQLite3` accept a `:load_extensions`
  option and apply it to every pooled connection:

      # config/runtime.exs
      config :my_app, MyApp.Repo,
        load_extensions: Localize.Ecto.SQLite3.Extension.load_extensions()

  `load_extensions/0` returns an empty list when the extension was not
  built, so the same configuration is safe in an environment that has
  not opted in — queries naming an ICU collation will then fail with
  SQLite's `no such collation sequence` error rather than at boot.

  """

  @extension "localize_icu"

  @doc """
  Returns the path of the compiled `localize_icu` extension.

  The path has no file extension. SQLite appends the platform's shared
  library suffix itself, which keeps the same path correct on macOS
  (`.dylib`) and Linux (`.so`).

  The file exists only if the extension was built; use `available?/0`
  to check, or `load_extensions/0` to get a list that is empty when it
  was not.

  ### Returns

  * The path as a string.

  ### Examples

      iex> Localize.Ecto.SQLite3.Extension.path() =~ "localize_icu"
      true

  """
  @spec path() :: String.t()
  def path do
    :localize_ecto
    |> Application.app_dir("priv")
    |> Path.join(@extension)
  end

  @doc """
  Returns whether the `localize_icu` extension has been built.

  ### Returns

  * `true` if the compiled extension is present.

  * `false` if the build was not opted in, or failed.

  ### Examples

      iex> is_boolean(Localize.Ecto.SQLite3.Extension.available?())
      true

  """
  @spec available?() :: boolean()
  def available? do
    path = path()

    File.exists?(path <> ".so") or File.exists?(path <> ".dylib") or
      File.exists?(path <> ".dll")
  end

  @doc """
  Returns the `:load_extensions` value for a SQLite repo or connection.

  ### Returns

  * `[path()]` if the extension is available.

  * `[]` if it is not, so that the configuration is safe to apply in an
    environment that has not built it.

  ### Examples

      iex> is_list(Localize.Ecto.SQLite3.Extension.load_extensions())
      true

  """
  @spec load_extensions() :: [String.t()]
  def load_extensions do
    if available?() do
      [path()]
    else
      []
    end
  end
end
