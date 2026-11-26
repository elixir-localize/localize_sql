defmodule Localize.Unit.Ecto.RangeQueryTest do
  # Values are stored in the base unit of their dimension, so an ordinary
  # comparison of two composites is a comparison of values within one
  # dimension: Postgres compares a row's fields in order, the unit and then
  # the value. A btree on the whole column serves it, index-only for a count.
  use ExUnit.Case, async: false

  import Ecto.Query
  import Localize.Unit.Ecto.Query

  alias Localize.Ecto.TestRepo
  alias Localize.Unit.DDL

  doctest Localize.Unit.Ecto.Query

  defmodule Measurement do
    @moduledoc false
    use Ecto.Schema

    schema "unit_range_rows" do
      field(:measure, Localize.Unit.Ecto.Composite.Type)
    end
  end

  defmodule Trip do
    @moduledoc false
    use Ecto.Schema

    schema "unit_range_trips" do
      field(:distance, Localize.UnitWithUsage.Ecto.Composite.Type)
    end
  end

  setup_all do
    quietly(DDL.drop_aggregate_functions())
    quietly(DDL.drop_cldr_unit())
    execute!(DDL.create_cldr_unit())
    execute!(DDL.define_aggregate_functions())
    execute!("CREATE TABLE unit_range_rows (id bigserial PRIMARY KEY, measure cldr_unit)")
    execute!("CREATE INDEX unit_range_rows_measure_index ON unit_range_rows (measure)")

    for {value, name} <- [
          {"500", "meter"},
          {"2", "kilometer"},
          {"3000", "foot"},
          {"5", "mile"},
          {"20", "celsius"}
        ] do
      {:ok, unit} = Localize.Unit.new(Decimal.new(value), name)
      TestRepo.insert!(%Measurement{measure: unit})
    end

    execute!(
      "CREATE TABLE unit_range_trips (id bigserial PRIMARY KEY, distance cldr_unit_with_usage)"
    )

    for {value, name} <- [{"5", "kilometer"}, {"20", "kilometer"}] do
      {:ok, unit} = Localize.Unit.new(Decimal.new(value), name, usage: "road")
      TestRepo.insert!(%Trip{distance: unit})
    end

    execute!("VACUUM ANALYZE unit_range_rows")

    on_exit(fn ->
      quietly("DROP TABLE IF EXISTS unit_range_rows")
      quietly("DROP TABLE IF EXISTS unit_range_trips")
      quietly(DDL.drop_aggregate_functions())
      quietly(DDL.drop_cldr_unit())
    end)

    :ok
  end

  defp unit(value, name) do
    {:ok, unit} = Localize.Unit.new(Decimal.new(value), name)
    unit
  end

  test "rows are stored in the base unit" do
    units =
      from(m in "unit_range_rows", select: fragment("(?).unit", m.measure))
      |> TestRepo.all()
      |> Enum.sort()

    assert units == ["kelvin", "meter", "meter", "meter", "meter"]
  end

  test "a range in any unit of the dimension selects by value" do
    # 1000 foot is 304.8 meter and 1 mile is 1609.344 meter, so the range
    # holds 500 meter and 3000 foot (914.4 meter), not 2 kilometer.
    low = unit("1000", "foot")
    high = unit("1", "mile")

    values =
      from(m in Measurement,
        where: m.measure >= cldr_unit(^low) and m.measure <= cldr_unit(^high),
        select: m.measure
      )
      |> TestRepo.all()
      |> Enum.map(&Decimal.to_string(Decimal.normalize(&1.value), :normal))
      |> Enum.sort()

    assert values == ["500", "914.4"]
  end

  test "a range of one dimension never selects another" do
    count =
      from(m in Measurement,
        where:
          m.measure >= cldr_unit(^unit("0", "meter")) and
            m.measure <= cldr_unit(^unit("1000000", "meter")),
        select: count()
      )
      |> TestRepo.one()

    assert count == 4
  end

  test "a btree on the whole column can serve the range" do
    plan =
      TestRepo.transaction(fn ->
        TestRepo.query!("SET LOCAL enable_seqscan = off")

        {sql, params} =
          TestRepo.to_sql(
            :all,
            from(m in Measurement,
              where:
                m.measure >= cldr_unit(^unit("100", "meter")) and
                  m.measure <= cldr_unit(^unit("3", "kilometer")),
              select: count()
            )
          )

        TestRepo.query!("EXPLAIN " <> sql, params).rows
        |> Enum.map_join("\n", &hd/1)
      end)

    assert {:ok, text} = plan
    assert text =~ "Index Only Scan using unit_range_rows_measure_index"
  end

  test "unit_between/3 selects inclusively, in any unit of the dimension" do
    values =
      from(m in Measurement,
        where: unit_between(m.measure, ^unit("500", "meter"), ^unit("2", "kilometer")),
        select: m.measure
      )
      |> TestRepo.all()
      |> Enum.map(&Decimal.to_string(Decimal.normalize(&1.value), :normal))
      |> Enum.sort()

    assert values == ["2000", "500", "914.4"]
  end

  describe "the unit aggregates" do
    # The four meter rows: 500, 2000, 914.4 (3000 foot) and 8046.72 (5 mile).
    defp meters do
      from(m in Measurement,
        where: unit_between(m.measure, ^unit("0", "meter"), ^unit("1000000", "meter"))
      )
    end

    test "sum, avg, min and max load as units in the base unit" do
      [sum, avg, min, max] =
        meters()
        |> select([m], [
          unit_sum(m.measure),
          unit_avg(m.measure),
          unit_min(m.measure),
          unit_max(m.measure)
        ])
        |> TestRepo.one()

      assert sum.name == "meter"
      assert Decimal.equal?(sum.value, Decimal.new("11461.12"))
      assert Decimal.equal?(Decimal.round(avg.value, 2), Decimal.new("2865.28"))
      assert Decimal.equal?(min.value, Decimal.new("500"))
      assert Decimal.equal?(max.value, Decimal.new("8046.72"))
    end

    test "an empty set aggregates to nil" do
      empty =
        from(m in Measurement,
          where: unit_between(m.measure, ^unit("1", "parsec"), ^unit("2", "parsec")),
          select: unit_sum(m.measure)
        )
        |> TestRepo.one()

      assert is_nil(empty)
    end

    test "a set of more than one unit raises" do
      exception =
        assert_raise Postgrex.Error, fn ->
          TestRepo.one(from(m in Measurement, select: unit_sum(m.measure)))
        end

      assert exception.postgres.pg_code == "22033"

      assert exception.postgres.message =~ "Incompatible unit names"
    end
  end

  test "cldr_unit_with_usage/1 compares within a usage" do
    {:ok, lower} = Localize.Unit.new(Decimal.new("10"), "kilometer", usage: "road")

    count =
      from(t in Trip, where: t.distance >= cldr_unit_with_usage(^lower), select: count())
      |> TestRepo.one()

    assert count == 1
  end

  defp execute!(sql) do
    sql
    |> String.split("\n\n\n", trim: true)
    |> Enum.each(&TestRepo.query!/1)
  end

  defp quietly(sql) do
    sql
    |> String.split("\n\n\n", trim: true)
    |> Enum.each(&TestRepo.query/1)
  end
end
