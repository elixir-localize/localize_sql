defmodule Localize.Unit.DDLSQLTest do
  # Installs database-global composite types and aggregates.
  use ExUnit.Case, async: false

  alias Localize.Ecto.TestRepo
  alias Localize.Unit.DDL

  setup_all do
    # A clean database has neither the types nor the functions; the drop
    # statements name the types in their signatures, so they are run
    # permissively rather than asserted.
    quietly(DDL.drop_aggregate_functions())
    quietly(DDL.drop_cldr_unit())
    execute!(DDL.create_cldr_unit())
    execute!(DDL.define_aggregate_functions())

    execute!("CREATE TABLE IF NOT EXISTS unit_rows (id serial, measure cldr_unit)")

    execute!(
      "CREATE TABLE IF NOT EXISTS unit_usage_rows (id serial, measure cldr_unit_with_usage)"
    )

    on_exit(fn ->
      quietly("DROP TABLE IF EXISTS unit_rows")
      quietly("DROP TABLE IF EXISTS unit_usage_rows")
      quietly(DDL.drop_aggregate_functions())
      quietly(DDL.drop_cldr_unit())
    end)

    :ok
  end

  setup do
    execute!("TRUNCATE unit_rows")
    execute!("TRUNCATE unit_usage_rows")
    :ok
  end

  describe "cldr_unit aggregates" do
    test "sum, min, max and avg over the same unit" do
      insert("metre", "2.5")
      insert("metre", "1.5")
      insert("metre", "6.0")

      assert one("SELECT sum(measure)::text FROM unit_rows") == "(metre,10.0)"
      assert one("SELECT min(measure)::text FROM unit_rows") == "(metre,1.5)"
      assert one("SELECT max(measure)::text FROM unit_rows") == "(metre,6.0)"
      assert one("SELECT avg(measure)::text FROM unit_rows") =~ "(metre,3.33"
    end

    test "adding different units raises" do
      insert("metre", "2.5")
      insert("foot", "1.0")

      exception =
        assert_raise Postgrex.Error, fn -> one("SELECT sum(measure)::text FROM unit_rows") end

      assert exception.postgres.message =~ "Incompatible unit names"
    end
  end

  describe "cldr_unit_with_usage aggregates" do
    test "carry the usage through sum" do
      insert_usage("metre", "2.5", "road")
      insert_usage("metre", "1.5", "road")

      assert one("SELECT sum(measure)::text FROM unit_usage_rows") == "(metre,4.0,road)"
    end

    # avg over a type with an extra field exercises the generated
    # intermediate state type, which carries the extra column alongside
    # the running sum and count.
    test "carry the usage through avg" do
      insert_usage("metre", "2.0", "road")
      insert_usage("metre", "4.0", "road")

      assert one("SELECT avg(measure)::text FROM unit_usage_rows") ==
               "(metre,3.0000000000000000,road)"
    end

    test "min and max carry the usage" do
      insert_usage("litre", "1.0", "fluid")
      insert_usage("litre", "9.0", "fluid")

      assert one("SELECT min(measure)::text FROM unit_usage_rows") == "(litre,1.0,fluid)"
      assert one("SELECT max(measure)::text FROM unit_usage_rows") == "(litre,9.0,fluid)"
    end
  end

  defp insert(unit, value) do
    execute!("INSERT INTO unit_rows (measure) VALUES (ROW('#{unit}', #{value})::cldr_unit)")
  end

  defp insert_usage(unit, value, usage) do
    execute!(
      "INSERT INTO unit_usage_rows (measure) VALUES (ROW('#{unit}', #{value}, '#{usage}')::cldr_unit_with_usage)"
    )
  end

  defp execute!(sql) do
    sql |> String.split("\n\n\n") |> Enum.each(&TestRepo.query!/1)
  end

  defp quietly(sql) do
    sql |> String.split("\n\n\n") |> Enum.each(&TestRepo.query(&1))
  end

  defp one(sql) do
    [[value]] = TestRepo.query!(sql).rows
    value
  end
end
