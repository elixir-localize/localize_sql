if Code.ensure_loaded?(Ecto.Query) do
  defmodule Localize.Unit.Ecto.Query do
    @moduledoc """
    Query expressions for comparing units stored in the `cldr_unit` and
    `cldr_unit_with_usage` composite types.

    The unit Ecto types store a value in the base unit of its dimension,
    so `2 kilometer` is stored as `2000 meter`. PostgreSQL compares two
    composite values field by field, the unit and then the value, so a
    comparison of two stored units is a comparison of their values within
    one dimension, and a range whose bounds are in one dimension never
    selects a value of another.

    A bound has to reach PostgreSQL as a value of the composite type.
    Compared with a column, a parameter is otherwise read as an anonymous
    `record`, which Postgrex cannot encode. `cldr_unit/1` and
    `cldr_unit_with_usage/1` dump a bound through the Ecto type, in the
    base unit, and cast it to the composite type, so a bound may be given
    in any unit of the dimension:

        import Ecto.Query
        import Localize.Unit.Ecto.Query

        from m in Measurement, where: m.distance >= cldr_unit(^lower)

        from m in Measurement, where: unit_between(m.distance, ^lower, ^upper)

    ### Indexes

    An ordinary btree on the column serves these comparisons, and since
    every value of a dimension shares its base unit it orders them by
    value. A count over a range is then an index-only scan:

        create index(:measurements, [:distance])

    ### Aggregates

    `unit_sum/1`, `unit_avg/1`, `unit_min/1` and `unit_max/1` aggregate a
    `cldr_unit` column with PostgreSQL's own aggregates over its fields,
    which run in parallel, and raise when a set holds more than one unit,
    as the `sum`, `avg`, `min` and `max` aggregates of
    `Localize.Unit.DDL` do. They are about four times faster than those
    aggregates, which are written in PL/pgSQL. The mismatch is raised by
    the `cldr_unit_mismatch` function that
    `Localize.Unit.DDL.define_aggregate_functions/1` creates.

        from m in Measurement, select: unit_sum(m.distance)

    """

    @doc """
    Casts a unit to a `cldr_unit` query parameter in the base unit of its
    dimension.

    ### Arguments

    * `value` is a pinned `t:Localize.Unit.t/0` (`^value`), in any unit
      of its dimension.

    ### Returns

    * A query fragment `value::cldr_unit`, whose parameter is the unit in
      its base unit, for comparison with a `cldr_unit` column.

    ### Examples

        iex> import Ecto.Query
        iex> {:ok, lower} = Localize.Unit.new(1, "kilometer")
        iex> query = from m in "measurements", where: m.distance >= cldr_unit(^lower), select: m.id
        iex> match?(%Ecto.Query{}, query)
        true

    """
    defmacro cldr_unit(value) do
      quote do
        fragment(
          "?::cldr_unit",
          type(unquote(value), Localize.Unit.Ecto.Composite.Type)
        )
      end
    end

    @doc """
    Casts a unit to a `cldr_unit_with_usage` query parameter in the base
    unit of its dimension.

    The usage is the third field of the composite, so it orders values
    that are equal: compare with a bound of the same usage.

    ### Arguments

    * `value` is a pinned `t:Localize.Unit.t/0` (`^value`), in any unit
      of its dimension, with or without a usage.

    ### Returns

    * A query fragment `value::cldr_unit_with_usage`, whose parameter is
      the unit in its base unit, for comparison with a
      `cldr_unit_with_usage` column.

    ### Examples

        iex> import Ecto.Query
        iex> {:ok, lower} = Localize.Unit.new(1, "kilometer", usage: "road")
        iex> query = from t in "trips", where: t.distance >= cldr_unit_with_usage(^lower), select: t.id
        iex> match?(%Ecto.Query{}, query)
        true

    """
    defmacro cldr_unit_with_usage(value) do
      quote do
        fragment(
          "?::cldr_unit_with_usage",
          type(unquote(value), Localize.UnitWithUsage.Ecto.Composite.Type)
        )
      end
    end

    @doc """
    Tests whether a `cldr_unit` lies between two units, inclusive.

    Both bounds are dumped in the base unit of their dimension, so they
    may be given in any unit of it. A row of another dimension is never
    between them.

    ### Arguments

    * `expression` is an Ecto query expression that evaluates to a
      `cldr_unit`.

    * `lower` is a pinned `t:Localize.Unit.t/0` (`^lower`).

    * `upper` is a pinned `t:Localize.Unit.t/0` (`^upper`) of the same
      dimension as `lower`.

    ### Returns

    * A boolean query fragment
      `expression BETWEEN lower::cldr_unit AND upper::cldr_unit`.

    ### Examples

        iex> import Ecto.Query
        iex> {:ok, lower} = Localize.Unit.new(500, "meter")
        iex> {:ok, upper} = Localize.Unit.new(1, "mile")
        iex> query = from m in "measurements", where: unit_between(m.distance, ^lower, ^upper), select: m.id
        iex> match?(%Ecto.Query{}, query)
        true

    """
    defmacro unit_between(expression, lower, upper) do
      quote do
        fragment(
          "? BETWEEN ?::cldr_unit AND ?::cldr_unit",
          unquote(expression),
          type(unquote(lower), Localize.Unit.Ecto.Composite.Type),
          type(unquote(upper), Localize.Unit.Ecto.Composite.Type)
        )
      end
    end

    @doc """
    Sums a `cldr_unit` column.

    ### Arguments

    * `expression` is an Ecto query expression that evaluates to a
      `cldr_unit`.

    ### Returns

    * A query expression that loads as a `t:Localize.Unit.t/0` in the
      base unit, or `nil` for an empty set. A set holding more than one
      unit raises a PostgreSQL error with SQLSTATE `22033`.

    ### Examples

        iex> import Ecto.Query
        iex> query = from m in "measurements", select: unit_sum(m.distance)
        iex> match?(%Ecto.Query{}, query)
        true

    """
    defmacro unit_sum(expression) do
      guarded_aggregate("sum", expression)
    end

    @doc """
    Averages a `cldr_unit` column.

    ### Arguments

    * `expression` is an Ecto query expression that evaluates to a
      `cldr_unit`.

    ### Returns

    * A query expression that loads as a `t:Localize.Unit.t/0` in the
      base unit, or `nil` for an empty set. A set holding more than one
      unit raises a PostgreSQL error with SQLSTATE `22033`.

    ### Examples

        iex> import Ecto.Query
        iex> query = from m in "measurements", select: unit_avg(m.distance)
        iex> match?(%Ecto.Query{}, query)
        true

    """
    defmacro unit_avg(expression) do
      guarded_aggregate("avg", expression)
    end

    @doc """
    Returns the least value of a `cldr_unit` column.

    ### Arguments

    * `expression` is an Ecto query expression that evaluates to a
      `cldr_unit`.

    ### Returns

    * A query expression that loads as a `t:Localize.Unit.t/0` in the
      base unit, or `nil` for an empty set. A set holding more than one
      unit raises a PostgreSQL error with SQLSTATE `22033`.

    ### Examples

        iex> import Ecto.Query
        iex> query = from m in "measurements", select: unit_min(m.distance)
        iex> match?(%Ecto.Query{}, query)
        true

    """
    defmacro unit_min(expression) do
      guarded_aggregate("min", expression)
    end

    @doc """
    Returns the greatest value of a `cldr_unit` column.

    ### Arguments

    * `expression` is an Ecto query expression that evaluates to a
      `cldr_unit`.

    ### Returns

    * A query expression that loads as a `t:Localize.Unit.t/0` in the
      base unit, or `nil` for an empty set. A set holding more than one
      unit raises a PostgreSQL error with SQLSTATE `22033`.

    ### Examples

        iex> import Ecto.Query
        iex> query = from m in "measurements", select: unit_max(m.distance)
        iex> match?(%Ecto.Query{}, query)
        true

    """
    defmacro unit_max(expression) do
      guarded_aggregate("max", expression)
    end

    # PostgreSQL's aggregate over the values, when every row of the set
    # has one unit; `cldr_unit_mismatch` raises otherwise. An empty set
    # has no unit and aggregates to NULL. The SQL must be a literal for
    # `fragment/1`, so it is built here, when the macro expands.
    defp guarded_aggregate(aggregate, expression) do
      sql =
        "CASE WHEN min((?).unit) IS NULL THEN NULL " <>
          "WHEN min((?).unit) = max((?).unit) " <>
          "THEN ROW(min((?).unit), #{aggregate}((?).value))::cldr_unit " <>
          "ELSE cldr_unit_mismatch(min((?).unit), max((?).unit)) END"

      arguments = List.duplicate(expression, 7)

      quote do
        type(
          fragment(unquote(sql), unquote_splicing(arguments)),
          Localize.Unit.Ecto.Composite.Type
        )
      end
    end
  end
end
