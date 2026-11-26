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
  end
end
