if Code.ensure_loaded?(Mix.Ecto) do
  defmodule Mix.Tasks.Localize.Unit.Gen.Migration do
    @shortdoc "Generates a migration creating the cldr_unit types and aggregates"

    @moduledoc """
    Generates an Ecto migration that installs the unit composite types and
    their aggregate functions into a PostgreSQL database.

    The migration creates the `cldr_unit` and `cldr_unit_with_usage`
    composite types and their `sum`, `min`, `max` and `avg` aggregates, so
    that `Localize.Unit.Ecto.Composite.Type` columns can be summed and
    averaged in the database. See `Localize.Unit.DDL`.

        mix localize.unit.gen.migration -r MyApp.Repo

    ### Options

    * `-r`, `--repo` is the repository to generate the migration for, as
      `Mix.Ecto` accepts it. The default is the application's configured
      repository.

    """

    use Mix.Task

    import Mix.Ecto

    alias Localize.Ecto.Migration.Generator
    alias Localize.Unit.DDL

    @impl Mix.Task
    def run(args) do
      Mix.Task.run("app.config")

      up =
        Enum.map_join(
          [&DDL.create_cldr_unit/0, &DDL.define_aggregate_functions/0],
          "\n",
          &execute/1
        )

      down =
        Enum.map_join([&DDL.drop_aggregate_functions/0, &DDL.drop_cldr_unit/0], "\n", &execute/1)

      for repo <- parse_repo(args) do
        ensure_repo(repo, args)
        file = Generator.create_migration(repo, "add_cldr_unit", up, down, Generator.timestamp())
        Mix.shell().info("Generated #{file}")
      end
    end

    defp execute(ddl_function) do
      DDL.execute_each(ddl_function.())
    end
  end
end
