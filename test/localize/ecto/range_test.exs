defmodule Localize.Ecto.RangeTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Localize.Ecto.Range

  doctest Localize.Ecto.Range

  describe "the generated SQL" do
    test "operators expand to the PostgreSQL range operators" do
      for {sql, query} <- [
            {"@>", from(b in "bookings", where: contains(b.period, b.other), select: b.id)},
            {"<@", from(b in "bookings", where: contained_by(b.other, b.period), select: b.id)},
            {"&&", from(b in "bookings", where: overlaps(b.period, b.other), select: b.id)},
            {"-|-", from(b in "bookings", where: adjacent(b.period, b.other), select: b.id)},
            {"<<",
             from(b in "bookings", where: strictly_before(b.period, b.other), select: b.id)},
            {">>", from(b in "bookings", where: strictly_after(b.period, b.other), select: b.id)}
          ] do
        assert to_sql(query) =~ sql
      end
    end

    test "set operations expand to the PostgreSQL range operators" do
      assert to_sql(from(b in "bookings", select: range_union(b.period, b.other))) =~ "+"
      assert to_sql(from(b in "bookings", select: range_intersection(b.period, b.other))) =~ "*"
      assert to_sql(from(b in "bookings", select: range_difference(b.period, b.other))) =~ "-"
    end

    # Ecto.Query exports union/2, intersect/2 and except/2 for combining
    # result sets. The range set operations combine two values in a row,
    # so they carry distinct names and both modules can be imported.
    test "the set operations do not collide with the query set operations" do
      cancellations = from(c in "cancellations", select: range_union(c.period, c.other))
      query = union(from(b in "bookings", select: range_union(b.period, b.other)), ^cancellations)

      assert to_sql(query) =~ "UNION"
    end

    test "accessors expand to the PostgreSQL range functions" do
      assert to_sql(from(b in "bookings", select: lower_bound(b.period))) =~ "lower("
      assert to_sql(from(b in "bookings", select: upper_bound(b.period))) =~ "upper("
      assert to_sql(from(b in "bookings", where: is_empty(b.period), select: b.id)) =~ "isempty("
    end

    test "aggregates expand to the PostgreSQL range aggregates" do
      assert to_sql(from(b in "bookings", select: range_agg(b.period))) =~ "range_agg("

      assert to_sql(from(b in "bookings", select: range_intersect_agg(b.period))) =~
               "range_intersect_agg("
    end

    # Localize.Ecto.Postgres.lower/1 is locale-aware case mapping. Both
    # modules are meant to be imported into the same query module, so the
    # range accessors carry a different name.
    test "the range accessors do not collide with the case-mapping macros" do
      import Localize.Ecto.Postgres

      query = from(b in "bookings", select: {lower(b.name, "tr"), lower_bound(b.period)})

      assert to_sql(query) =~ "lower("
    end
  end

  defp to_sql(query) do
    {query, _cast_params, _dump_params} =
      Ecto.Adapter.Queryable.plan_query(:all, Ecto.Adapters.Postgres, query)

    IO.iodata_to_binary(Ecto.Adapters.Postgres.Connection.all(query))
  end
end
