defmodule Localize.Ecto.Migration.Generator do
  @moduledoc """
  Writes a migration file into a repository, for the migration-generating
  mix tasks of `localize_sql`.

  A tagged decimal type is installed by running SQL — `CREATE TYPE`, the
  aggregate functions — inside an Ecto migration. Rather than ship the
  SQL as a file the consumer copies, these tasks generate a migration
  whose `up` and `down` embed the SQL produced by a `DDL` module, so the
  statements are baked into the consumer's own timestamped migration and
  are not affected by a later upgrade of `localize_sql`.

  This module renders and writes that migration. `render/3` builds the
  source and is independent of any repository; `create_migration/5`
  writes it into a repository's migrations directory.
  """

  @doc """
  Renders a migration module as formatted Elixir source.

  ### Arguments

  * `module` is the migration module name.

  * `up_sql` is the body of the `up/0` function — typically the output
    of a `DDL.execute_each/1` call.

  * `down_sql` is the body of the `down/0` function.

  ### Returns

  * The migration source as a string.

  ### Examples

      iex> source = Localize.Ecto.Migration.Generator.render(
      ...>   MyApp.Repo.Migrations.AddCldrUnit,
      ...>   ~s|execute "CREATE TYPE public.cldr_unit AS (unit varchar, value numeric);"|,
      ...>   ~s|execute "DROP TYPE public.cldr_unit;"|
      ...> )
      iex> source =~ "def up do"
      true

  """
  @spec render(module(), String.t(), String.t()) :: String.t()
  def render(module, up_sql, down_sql) do
    """
    defmodule #{inspect(module)} do
      use Ecto.Migration

      def up do
        #{up_sql}
      end

      def down do
        #{down_sql}
      end
    end
    """
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  if Code.ensure_loaded?(Mix.Generator) and Code.ensure_loaded?(Ecto.Migrator) do
    @doc """
    Writes a migration into a repository's migrations directory.

    ### Arguments

    * `repo` is an `Ecto.Repo` module.

    * `name` is the migration name in snake case, such as
      `"add_cldr_unit"`. It is timestamped and camelized into the module
      name.

    * `up_sql` is the body of the `up/0` function.

    * `down_sql` is the body of the `down/0` function.

    * `timestamp` is the 14-digit migration timestamp string, from
      `timestamp/0`.

    ### Returns

    * The path of the written file.

    ### Examples

    A migration-generating mix task calls it with the SQL a `DDL` module
    renders:

        Localize.Ecto.Migration.Generator.create_migration(
          MyApp.Repo,
          "add_cldr_unit",
          up_sql,
          down_sql,
          Localize.Ecto.Migration.Generator.timestamp()
        )
        #=> "priv/repo/migrations/20260731090501_add_cldr_unit.exs"

    """
    @spec create_migration(module(), String.t(), String.t(), String.t(), String.t()) :: String.t()
    def create_migration(repo, name, up_sql, down_sql, timestamp) do
      directory = Path.relative_to(Ecto.Migrator.migrations_path(repo), Mix.Project.app_path())
      Mix.Generator.create_directory(directory)

      file = Path.join(directory, "#{timestamp}_#{name}.exs")
      module = Module.concat([repo, Migrations, Macro.camelize(name)])

      Mix.Generator.create_file(file, render(module, up_sql, down_sql))
      file
    end

    @doc """
    Returns a 14-digit UTC timestamp for a migration filename.

    ### Returns

    * The timestamp as a string, such as `"20260731090501"`.

    ### Examples

        iex> Localize.Ecto.Migration.Generator.timestamp() =~ ~r/\\A\\d{14}\\z/
        true

    """
    @spec timestamp() :: String.t()
    def timestamp do
      {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()
      "#{year}#{pad(month)}#{pad(day)}#{pad(hour)}#{pad(minute)}#{pad(second)}"
    end

    defp pad(number) when number < 10, do: "0#{number}"
    defp pad(number), do: to_string(number)
  end
end
