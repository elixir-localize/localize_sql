defmodule Localize.Unit.DDLTest do
  use ExUnit.Case, async: true

  doctest Localize.Unit.DDL

  alias Localize.Unit.DDL

  test "create_cldr_unit defines both composite types" do
    sql = DDL.create_cldr_unit()

    assert sql =~ "CREATE TYPE public.cldr_unit AS (unit varchar, value numeric);"

    assert sql =~
             "CREATE TYPE public.cldr_unit_with_usage AS (unit varchar, value numeric, usage varchar);"
  end

  test "the sum function keeps its historical name for both types" do
    sql = DDL.define_aggregate_functions()

    assert sql =~ "CREATE OR REPLACE FUNCTION unit_state_function(agg_state cldr_unit,"

    assert sql =~
             "CREATE OR REPLACE FUNCTION unit_with_usage_state_function(agg_state cldr_unit_with_usage,"
  end

  test "aggregates cover sum, min, max and avg for both types" do
    sql = DDL.define_aggregate_functions()

    for type <- ["cldr_unit", "cldr_unit_with_usage"],
        aggregate <- ["sum", "min", "max", "avg"] do
      assert sql =~ "AGGREGATE #{aggregate}(#{type})"
    end
  end

  test "drops name the with-usage function that was created" do
    sql = DDL.drop_aggregate_functions()

    assert sql =~
             "DROP FUNCTION IF EXISTS unit_with_usage_state_function(cldr_unit_with_usage, cldr_unit_with_usage);"
  end

  test "an unsupported database raises" do
    assert_raise ArgumentError, ~r/only :postgres/, fn -> DDL.create_cldr_unit(:mysql) end
  end
end
