defmodule Localize.Unit.DDL do
  @moduledoc """
  Generates the SQL that stores `t:Localize.Unit.t/0` values in PostgreSQL.

  A unit pairs a unit name with a decimal value — `2.5` metres, `100`
  kilometres — and is stored as a tagged decimal composite type so that
  the database can add and aggregate units while refusing to add metres
  to feet. This module returns the SQL creating those types and their
  aggregate functions; it is a thin wrapper over
  `Localize.Ecto.TaggedDecimal.DDL`, supplying the unit specifications.

  Two composite types are created. `cldr_unit(unit, value)` stores a unit
  and its value; `cldr_unit_with_usage(unit, value, usage)` additionally
  preserves the unit's usage (`:road` versus `:rainfall`, say) across the
  round trip. Each has `sum`, `min`, `max` and `avg` aggregates that
  raise on a unit-name mismatch.

  ### Migrations

  The generated statements install into a migration with `execute/1` and
  `execute_each/1`, which `mix localize.unit.gen.migration` does
  automatically:

      defmodule MyApp.Repo.Migrations.AddCldrUnit do
        use Ecto.Migration

        def up do
          Localize.Unit.DDL.execute_each(Localize.Unit.DDL.create_cldr_unit())
          Localize.Unit.DDL.execute_each(Localize.Unit.DDL.define_aggregate_functions())
        end

        def down do
          Localize.Unit.DDL.execute_each(Localize.Unit.DDL.drop_aggregate_functions())
          Localize.Unit.DDL.execute_each(Localize.Unit.DDL.drop_cldr_unit())
        end
      end

  """

  alias Localize.Ecto.TaggedDecimal
  alias Localize.Ecto.TaggedDecimal.DDL

  @typedoc """
  The target database. Only PostgreSQL is supported; the argument exists
  so the API can grow without changing.
  """
  @type db_type :: :postgres

  @statement_separator "\n\n\n"

  # The unit aggregate functions were originally named `unit_state_function`
  # (and `unit_with_usage_state_function`) without the `sum` infix the
  # default naming would give them. The override keeps those historical
  # names so an existing database is undisturbed.
  @unit_spec TaggedDecimal.new!(
               type_name: "cldr_unit",
               tag_field: "unit",
               value_field: "value",
               function_prefix: "unit",
               argument_name: "unit",
               tag_description: "unit name",
               function_names: %{sum_state: "unit_state_function"}
             )

  @unit_with_usage_spec TaggedDecimal.new!(
                          type_name: "cldr_unit_with_usage",
                          tag_field: "unit",
                          value_field: "value",
                          function_prefix: "unit_with_usage",
                          argument_name: "unit",
                          tag_description: "unit name",
                          extra_fields: [{"usage", "varchar"}],
                          function_names: %{sum_state: "unit_with_usage_state_function"}
                        )

  @specs [@unit_spec, @unit_with_usage_spec]

  @doc """
  Returns the SQL creating the `cldr_unit` and `cldr_unit_with_usage`
  composite types.

  ### Arguments

  * `db_type` is the target database. Only `:postgres` is supported. The
    default is `:postgres`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> Localize.Unit.DDL.create_cldr_unit() =~ "CREATE TYPE public.cldr_unit AS"
      true

  """
  @spec create_cldr_unit(db_type()) :: String.t()
  def create_cldr_unit(db_type \\ :postgres) do
    ensure_postgres!(db_type)
    join(Enum.map(@specs, &DDL.create_type/1))
  end

  @doc """
  Returns the SQL dropping the `cldr_unit` and `cldr_unit_with_usage`
  composite types.

  ### Arguments

  * `db_type` is the target database. Only `:postgres` is supported. The
    default is `:postgres`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> Localize.Unit.DDL.drop_cldr_unit() =~ "DROP TYPE public.cldr_unit_with_usage;"
      true

  """
  @spec drop_cldr_unit(db_type()) :: String.t()
  def drop_cldr_unit(db_type \\ :postgres) do
    ensure_postgres!(db_type)
    join(@specs |> Enum.reverse() |> Enum.map(&DDL.drop_type/1))
  end

  @doc """
  Returns the SQL defining the `sum`, `min`, `max` and `avg` aggregates
  for both unit composite types.

  ### Arguments

  * `db_type` is the target database. Only `:postgres` is supported. The
    default is `:postgres`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> Localize.Unit.DDL.define_aggregate_functions() =~ "CREATE OR REPLACE AGGREGATE sum(cldr_unit)"
      true

  """
  @spec define_aggregate_functions(db_type()) :: String.t()
  def define_aggregate_functions(db_type \\ :postgres) do
    ensure_postgres!(db_type)

    join(
      Enum.flat_map(@specs, fn spec ->
        [
          DDL.define_sum_function(spec),
          DDL.define_minmax_functions(spec),
          DDL.define_avg_function(spec)
        ]
      end)
    )
  end

  @doc """
  Returns the SQL dropping the aggregates and their functions for both
  unit composite types.

  ### Arguments

  * `db_type` is the target database. Only `:postgres` is supported. The
    default is `:postgres`.

  ### Returns

  * The SQL statements as a string, separated by two blank lines.

  ### Examples

      iex> Localize.Unit.DDL.drop_aggregate_functions() =~ "DROP AGGREGATE IF EXISTS avg(cldr_unit);"
      true

  """
  @spec drop_aggregate_functions(db_type()) :: String.t()
  def drop_aggregate_functions(db_type \\ :postgres) do
    ensure_postgres!(db_type)

    join(
      Enum.flat_map(@specs, fn spec ->
        [
          DDL.drop_avg_function(spec),
          DDL.drop_minmax_functions(spec),
          DDL.drop_sum_function(spec)
        ]
      end)
    )
  end

  @doc """
  Wraps a SQL string as a single `execute` call for a migration.

  See `Localize.Ecto.TaggedDecimal.DDL.execute/2`.

  ### Arguments

  * `sql` is a SQL string.

  ### Returns

  * The `execute` call as a string.

  ### Examples

      iex> Localize.Unit.DDL.execute("DROP TYPE public.cldr_unit;")
      "execute \\"DROP TYPE public.cldr_unit;\\""

  """
  @spec execute(String.t()) :: String.t()
  defdelegate execute(sql), to: DDL

  @doc """
  Wraps each statement of a SQL string as its own `execute` call.

  See `Localize.Ecto.TaggedDecimal.DDL.execute_each/2`.

  ### Arguments

  * `sql` is a SQL string possibly containing several statements.

  ### Returns

  * The `execute` calls as a string, one per statement.

  ### Examples

      iex> Localize.Unit.DDL.execute_each(Localize.Unit.DDL.drop_cldr_unit()) =~ "execute"
      true

  """
  @spec execute_each(String.t()) :: String.t()
  defdelegate execute_each(sql), to: DDL

  defp ensure_postgres!(:postgres), do: :ok

  defp ensure_postgres!(db_type) do
    raise ArgumentError,
          "Localize.Unit.DDL supports only :postgres, got #{inspect(db_type)}"
  end

  defp join(statements) do
    Enum.join(statements, @statement_separator)
  end
end
