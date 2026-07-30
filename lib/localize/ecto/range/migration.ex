if Code.ensure_loaded?(Ecto.Migration) do
  defmodule Localize.Ecto.Range.Migration do
    @moduledoc """
    Migration helpers for PostgreSQL range types.

    PostgreSQL provides range types over numbers, dates and timestamps,
    so most range columns need no migration beyond naming the type:

        add :period, :daterange

    Two things do need a migration. There is no built-in range over time
    of day, which `create_time_range/1` supplies, and the constraint that
    makes ranges worth using — that no two rows may overlap — is an
    exclusion constraint, which `no_overlap/3` builds:

        defmodule MyApp.Repo.Migrations.AddBookings do
          use Ecto.Migration

          import Localize.Ecto.Range.Migration

          def change do
            create_btree_gist()

            create table(:bookings) do
              add :room_id, references(:rooms), null: false
              add :period, :tstzrange, null: false
            end

            create no_overlap(:bookings, :period, scope: [:room_id])
          end
        end

    With that constraint in place, two bookings of the same room whose
    periods overlap are rejected by the database, whatever the
    application does.

    """

    @default_time_range "timerange"

    @doc """
    Creates a range type over time of day.

    PostgreSQL ships ranges over `integer`, `bigint`, `numeric`, `date`,
    `timestamp` and `timestamptz`, but not over `time`. This creates one,
    which is what opening hours and shift patterns need.

    Postgrex discovers the new type when a connection pool starts, and
    decodes it to a `t:Postgrex.Range.t/0` of `t:Time.t/0` with no
    further configuration. Because discovery happens at connection time,
    the type must be created in a migration rather than at runtime — a
    pool already running when the type is created does not know it.

    The operation is reversible.

    ### Arguments

    * `options` is a keyword list of options.

    ### Options

    * `:name` is the name of the range type. The default is
      `"timerange"`.

    * `:subtype` is the SQL type the range spans. The default is
      `"time"`; pass `"timetz"` for a range over time with time zone.

    ### Returns

    * `:ok`.

    ### Examples

        create_time_range()

        create_time_range(name: "opening_hours")

    """
    @spec create_time_range(Keyword.t()) :: :ok
    def create_time_range(options \\ []) do
      {create, drop} = time_range_sql_pair(options)
      Ecto.Migration.execute(create, drop)
    end

    @doc """
    Drops a range type over time of day.

    The operation is reversible: rolling back recreates the type from the
    same arguments.

    ### Arguments

    * `options` is a keyword list of options. See `create_time_range/1`.

    ### Returns

    * `:ok`.

    ### Examples

        drop_time_range()

        drop_time_range(name: "opening_hours")

    """
    @spec drop_time_range(Keyword.t()) :: :ok
    def drop_time_range(options \\ []) do
      {create, drop} = time_range_sql_pair(options)
      Ecto.Migration.execute(drop, create)
    end

    @doc """
    Enables the `btree_gist` extension.

    An exclusion constraint is enforced by a GiST index, and GiST cannot
    index equality on ordinary scalar types such as `integer` or `uuid`
    without this extension. Any `no_overlap/3` constraint carrying a
    `:scope` therefore needs it, and creating the constraint fails with
    `data type integer has no default operator class` when it is absent.

    The operation is reversible. Enabling an extension requires database
    superuser privileges.

    ### Returns

    * `:ok`.

    ### Examples

        create_btree_gist()

    """
    @spec create_btree_gist() :: :ok
    def create_btree_gist do
      Ecto.Migration.execute(
        "CREATE EXTENSION IF NOT EXISTS btree_gist",
        "DROP EXTENSION IF EXISTS btree_gist"
      )
    end

    @doc """
    Returns an exclusion constraint forbidding overlapping ranges.

    The constraint rejects any two rows whose ranges overlap. A `:scope`
    narrows that to rows agreeing on other columns, which is almost
    always what is wanted — one room's bookings may not overlap each
    other, but they may freely overlap another room's.

    Pass the result to `Ecto.Migration.create/1`. A scoped constraint
    needs the `btree_gist` extension; see `create_btree_gist/0`.

    ### Arguments

    * `table` is the table name as an atom or string.

    * `column` is the range column as an atom or string.

    * `options` is a keyword list of options.

    ### Options

    * `:scope` is a list of columns that must agree for two rows to be
      considered in conflict. The default is `[]`, which forbids any two
      rows in the table from overlapping.

    * `:name` is the name of the constraint. The default is
      `"<table>_<column>_no_overlap"`.

    * `:where` is a SQL predicate restricting the constraint to rows
      matching it, such as `"status <> 'cancelled'"`, so that rows
      failing the predicate are exempt. The default is `nil`.

    ### Returns

    * An `t:Ecto.Migration.Constraint.t/0`.

    ### Examples

        create no_overlap(:bookings, :period, scope: [:room_id])

        create no_overlap(:bookings, :period, where: "status <> 'cancelled'")

    """
    @spec no_overlap(atom() | String.t(), atom() | String.t(), Keyword.t()) ::
            Ecto.Migration.Constraint.t()
    def no_overlap(table, column, options \\ []) do
      scope = Keyword.get(options, :scope, [])
      name = Keyword.get_lazy(options, :name, fn -> "#{table}_#{column}_no_overlap" end)

      elements =
        Enum.map_join(scope ++ [column], ", ", fn element ->
          operator = if element == column, do: "&&", else: "="

          ~s|#{quote_identifier(element)} WITH #{operator}|
        end)

      # Ecto emits `EXCLUDE USING <exclude>` and has no field for a
      # predicate, so a partial constraint carries its WHERE clause in
      # the same expression — which is where PostgreSQL's grammar puts
      # it anyway.
      exclude =
        case Keyword.get(options, :where) do
          nil -> "gist (#{elements})"
          where -> "gist (#{elements}) WHERE (#{where})"
        end

      Ecto.Migration.constraint(table, name, exclude: exclude)
    end

    defp time_range_sql_pair(options) do
      name = Keyword.get(options, :name, @default_time_range)
      subtype = Keyword.get(options, :subtype, "time")

      {"CREATE TYPE #{quote_identifier(name)} AS RANGE (subtype = #{subtype})",
       "DROP TYPE IF EXISTS #{quote_identifier(name)}"}
    end

    defp quote_identifier(identifier) do
      ~s|"#{String.replace(to_string(identifier), ~s|"|, ~s|""|)}"|
    end
  end
end
